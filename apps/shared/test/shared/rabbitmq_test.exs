defmodule Shared.RabbitMQTest do
  use ExUnit.Case

  alias Shared.Crypto
  alias Shared.Event
  alias Shared.RabbitMQ

  describe "constantes do modulo" do
    test "exchange e 'promocoes'" do
      assert RabbitMQ.exchange() == "promocoes"
    end

    test "exchange type e :topic" do
      assert RabbitMQ.exchange_type() == :topic
    end

    test "backoff inicial e 1 segundo" do
      assert RabbitMQ.initial_backoff() == 1_000
    end

    test "backoff maximo e 30 segundos" do
      assert RabbitMQ.max_backoff() == 30_000
    end
  end

  describe "start_link/1" do
    @tag :integration
    test "conecta ao RabbitMQ e registra com nome" do
      opts = [
        name: :test_rabbitmq_start,
        url: rabbitmq_url(),
        queues: []
      ]

      {:ok, pid} = RabbitMQ.start_link(opts)

      assert Process.alive?(pid)
      assert Process.whereis(:test_rabbitmq_start) == pid

      GenServer.stop(pid)
    end

    @tag :integration
    test "retorna erro com URL invalida" do
      opts = [
        name: :test_rabbitmq_bad_url,
        url: "amqp://guest:guest@host_inexistente:5672",
        queues: []
      ]

      # Deve iniciar o GenServer mas agendar reconnect
      # (nao crasheia no start_link)
      {:ok, pid} = RabbitMQ.start_link(opts)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end
  end

  describe "publish/3" do
    @tag :integration
    test "publica mensagem com sucesso" do
      {:ok, pid} = start_test_rabbitmq("publish_test", [])

      assert :ok = RabbitMQ.publish(pid, "promocao.recebida", "test payload")

      GenServer.stop(pid)
    end

    @tag :integration
    test "retorna erro quando nao ha conexao" do
      opts = [
        name: :test_rabbitmq_no_conn,
        url: "amqp://guest:guest@host_inexistente:5672",
        queues: []
      ]

      {:ok, pid} = RabbitMQ.start_link(opts)

      assert {:error, _} = RabbitMQ.publish(pid, "promocao.recebida", "test payload")

      GenServer.stop(pid)
    end
  end

  describe "subscribe/2" do
    @tag :integration
    test "registra callback e recebe mensagens" do
      fila = "fila_subscribe_test_#{System.unique_integer([:positive])}"
      routing_key = "promocao.teste"

      {:ok, pid} = start_test_rabbitmq("subscribe_test", [{fila, [routing_key]}])

      test_pid = self()

      RabbitMQ.subscribe(pid, fn rk, payload ->
        send(test_pid, {:mensagem_recebida, rk, payload})
      end)

      # Publica uma mensagem
      :ok = RabbitMQ.publish(pid, routing_key, "hello from test")

      # Deve receber via callback
      assert_receive {:mensagem_recebida, ^routing_key, "hello from test"}, 5_000

      GenServer.stop(pid)
    end

    @tag :integration
    test "recebe mensagens de multiplas routing keys" do
      fila = "fila_multi_test_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        start_test_rabbitmq("multi_test", [{fila, ["promocao.livro", "promocao.jogo"]}])

      test_pid = self()

      RabbitMQ.subscribe(pid, fn rk, payload ->
        send(test_pid, {:msg, rk, payload})
      end)

      :ok = RabbitMQ.publish(pid, "promocao.livro", "livro payload")
      :ok = RabbitMQ.publish(pid, "promocao.jogo", "jogo payload")

      assert_receive {:msg, "promocao.livro", "livro payload"}, 5_000
      assert_receive {:msg, "promocao.jogo", "jogo payload"}, 5_000

      GenServer.stop(pid)
    end

    @tag :integration
    test "nao recebe mensagens de routing keys nao bindadas" do
      fila = "fila_filter_test_#{System.unique_integer([:positive])}"

      {:ok, pid} = start_test_rabbitmq("filter_test", [{fila, ["promocao.livro"]}])

      test_pid = self()

      RabbitMQ.subscribe(pid, fn rk, payload ->
        send(test_pid, {:msg, rk, payload})
      end)

      # Publica em routing key diferente
      :ok = RabbitMQ.publish(pid, "promocao.jogo", "nao deveria chegar")

      refute_receive {:msg, _, _}, 1_000

      GenServer.stop(pid)
    end
  end

  describe "fluxo completo com Event" do
    @tag :integration
    test "publica evento assinado e consome com verificacao" do
      fila = "fila_e2e_test_#{System.unique_integer([:positive])}"
      routing_key = "promocao.recebida"

      {:ok, pid} = start_test_rabbitmq("e2e_test", [{fila, [routing_key]}])

      # Gera chaves e cria evento assinado
      {priv, pub} = Crypto.generate_key_pair()

      event =
        Event.new(routing_key, %{"nome" => "Clean Code"}, "gateway")
        |> Event.sign(priv)

      {:ok, json} = Event.Envelope.encode(event)

      test_pid = self()

      RabbitMQ.subscribe(pid, fn _rk, payload ->
        {:ok, decoded} = Event.Envelope.decode(payload)
        verified = Event.verify(decoded, pub)
        send(test_pid, {:verificado, verified, decoded})
      end)

      :ok = RabbitMQ.publish(pid, routing_key, json)

      assert_receive {:verificado, true, decoded_event}, 5_000
      assert decoded_event.type == routing_key
      assert decoded_event.payload == %{"nome" => "Clean Code"}
      assert decoded_event.source == "gateway"

      GenServer.stop(pid)
    end
  end

  describe "reconnect" do
    @tag :integration
    test "backoff dobra a cada falha ate o maximo" do
      # Testa a logica de calculo do backoff
      initial = RabbitMQ.initial_backoff()
      max = RabbitMQ.max_backoff()

      backoffs =
        Stream.iterate(initial, fn b -> min(b * 2, max) end)
        |> Enum.take(10)

      assert hd(backoffs) == 1_000
      assert Enum.at(backoffs, 1) == 2_000
      assert Enum.at(backoffs, 2) == 4_000
      assert Enum.at(backoffs, 3) == 8_000
      assert Enum.at(backoffs, 4) == 16_000
      assert Enum.at(backoffs, 5) == 30_000
      # Deve estabilizar no maximo
      assert Enum.at(backoffs, 6) == 30_000
    end
  end

  # --- Helpers ---

  defp rabbitmq_url do
    System.get_env("RABBITMQ_URL", "amqp://guest:guest@localhost")
  end

  defp start_test_rabbitmq(suffix, queues) do
    name = :"test_rabbitmq_#{suffix}_#{System.unique_integer([:positive])}"

    RabbitMQ.start_link(
      name: name,
      url: rabbitmq_url(),
      queues: queues,
      queue_opts: [auto_delete: true]
    )
  end
end
