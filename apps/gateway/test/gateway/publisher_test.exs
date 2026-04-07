defmodule Gateway.PublisherTest do
  use ExUnit.Case

  @moduletag :integration

  alias Gateway.Publisher
  alias Shared.{Crypto, Event.Envelope}

  describe "publish_promocao/1" do
    setup :start_rabbitmq

    test "publica evento promocao.recebida assinado", %{rabbitmq: rabbitmq} do
      ensure_gateway_keys!()
      test_pid = self()

      Shared.RabbitMQ.subscribe(rabbitmq, fn routing_key, payload ->
        send(test_pid, {:received, routing_key, payload})
      end)

      promo_data = %{
        "nome" => "Clean Code",
        "descricao" => "Livro sobre boas praticas",
        "preco_original" => 89.90,
        "preco_promocional" => 45.00,
        "categoria" => "livro",
        "loja" => "Amazon"
      }

      assert :ok = Publisher.publish_promocao(promo_data)

      assert_receive {:received, "promocao.recebida", json}, 5_000

      {:ok, event} = Envelope.decode(json)
      assert event.type == "promocao.recebida"
      assert event.source == "gateway"
      assert event.payload["nome"] == "Clean Code"
      assert event.payload["categoria"] == "livro"

      # Verifica assinatura com chave publica do gateway
      {:ok, pub} = Crypto.load_public_key("gateway")
      assert Shared.Event.verify(event, pub)
    end
  end

  describe "publish_voto/2" do
    setup :start_rabbitmq_voto

    test "publica evento promocao.voto assinado", %{rabbitmq: rabbitmq} do
      ensure_gateway_keys!()
      test_pid = self()

      Shared.RabbitMQ.subscribe(rabbitmq, fn routing_key, payload ->
        send(test_pid, {:received, routing_key, payload})
      end)

      assert :ok = Publisher.publish_voto("promo-123", 1)

      assert_receive {:received, "promocao.voto", json}, 5_000

      {:ok, event} = Envelope.decode(json)
      assert event.type == "promocao.voto"
      assert event.source == "gateway"
      assert event.payload["promo_id"] == "promo-123"
      assert event.payload["voto"] == 1
    end
  end

  # --- Helpers ---

  defp start_rabbitmq(_context) do
    fila = "test_publisher_#{System.unique_integer([:positive])}"

    {:ok, pid} =
      Shared.RabbitMQ.start_link(
        name: :gateway_rabbitmq,
        url: rabbitmq_url(),
        queues: [{fila, ["promocao.recebida"]}],
        queue_opts: [auto_delete: true]
      )

    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    %{rabbitmq: pid}
  end

  defp start_rabbitmq_voto(_context) do
    fila = "test_publisher_voto_#{System.unique_integer([:positive])}"

    {:ok, pid} =
      Shared.RabbitMQ.start_link(
        name: :gateway_rabbitmq,
        url: rabbitmq_url(),
        queues: [{fila, ["promocao.voto"]}],
        queue_opts: [auto_delete: true]
      )

    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    %{rabbitmq: pid}
  end

  defp rabbitmq_url do
    System.get_env("RABBITMQ_URL", "amqp://guest:guest@localhost")
  end

  defp ensure_gateway_keys! do
    case Crypto.load_private_key("gateway") do
      {:ok, _} ->
        :ok

      {:error, _} ->
        {priv, pub} = Crypto.generate_key_pair()
        Crypto.save_keys("gateway", priv, pub)
    end
  end
end
