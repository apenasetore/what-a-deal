defmodule Notificacao.ConsumerTest do
  use ExUnit.Case, async: true

  alias Notificacao.Consumer
  alias Shared.Crypto
  alias Shared.Event

  describe "handle_message/4 — evento valido" do
    setup do
      {promocao_priv, promocao_pub} = Crypto.generate_key_pair()
      {ranking_priv, ranking_pub} = Crypto.generate_key_pair()

      keys = %{
        "promocao.publicada" => {promocao_pub, "nova"},
        "promocao.destaque" => {ranking_pub, "hot deal"}
      }

      %{
        promocao_priv: promocao_priv,
        ranking_priv: ranking_priv,
        keys: keys
      }
    end

    test "publica notificacao 'nova' em promocao.<categoria> para promocao.publicada", %{
      promocao_priv: promocao_priv,
      keys: keys
    } do
      payload = %{"nome" => "Clean Code", "preco" => 45.0, "categoria" => "livro"}

      json =
        Event.new("promocao.publicada", payload, "promocao")
        |> Event.sign(promocao_priv)
        |> Event.Envelope.encode()
        |> elem(1)

      rabbitmq = start_fake_rabbitmq()

      assert :ok = Consumer.handle_message("promocao.publicada", json, keys, rabbitmq)

      assert_received {:published, "promocao.livro", notif_json}
      {:ok, notif} = Jason.decode(notif_json)
      assert notif["tipo"] == "nova"
      assert notif["categoria"] == "livro"
      assert notif["promo"]["nome"] == "Clean Code"
    end

    test "publica notificacao 'hot deal' em promocao.<categoria> para promocao.destaque", %{
      ranking_priv: ranking_priv,
      keys: keys
    } do
      payload = %{"nome" => "Clean Code", "categoria" => "livro"}

      json =
        Event.new("promocao.destaque", payload, "ranking")
        |> Event.sign(ranking_priv)
        |> Event.Envelope.encode()
        |> elem(1)

      rabbitmq = start_fake_rabbitmq()

      assert :ok = Consumer.handle_message("promocao.destaque", json, keys, rabbitmq)

      assert_received {:published, "promocao.livro", notif_json}
      {:ok, notif} = Jason.decode(notif_json)
      assert notif["tipo"] == "hot deal"
      assert notif["categoria"] == "livro"
    end

    test "notificacao de destaque contem a palavra literal 'hot deal'", %{
      ranking_priv: ranking_priv,
      keys: keys
    } do
      payload = %{"categoria" => "livro"}

      json =
        Event.new("promocao.destaque", payload, "ranking")
        |> Event.sign(ranking_priv)
        |> Event.Envelope.encode()
        |> elem(1)

      rabbitmq = start_fake_rabbitmq()

      Consumer.handle_message("promocao.destaque", json, keys, rabbitmq)

      assert_received {:published, _, notif_json}
      assert notif_json =~ "hot deal"
    end

    test "notificacao normal NAO contem 'hot deal'", %{
      promocao_priv: promocao_priv,
      keys: keys
    } do
      payload = %{"categoria" => "livro", "nome" => "X"}

      json =
        Event.new("promocao.publicada", payload, "promocao")
        |> Event.sign(promocao_priv)
        |> Event.Envelope.encode()
        |> elem(1)

      rabbitmq = start_fake_rabbitmq()

      Consumer.handle_message("promocao.publicada", json, keys, rabbitmq)

      assert_received {:published, _, notif_json}
      refute notif_json =~ "hot deal"
    end
  end

  describe "handle_message/4 — evento invalido" do
    setup do
      {promocao_priv, promocao_pub} = Crypto.generate_key_pair()
      {ranking_priv, ranking_pub} = Crypto.generate_key_pair()

      keys = %{
        "promocao.publicada" => {promocao_pub, "nova"},
        "promocao.destaque" => {ranking_pub, "hot deal"}
      }

      %{promocao_priv: promocao_priv, ranking_priv: ranking_priv, keys: keys}
    end

    test "descarta evento com assinatura adulterada", %{
      promocao_priv: promocao_priv,
      keys: keys
    } do
      original =
        Event.new("promocao.publicada", %{"categoria" => "livro", "nome" => "X"}, "promocao")
        |> Event.sign(promocao_priv)

      tampered = %{original | payload: %{"categoria" => "livro", "nome" => "Y"}}
      {:ok, json} = Event.Envelope.encode(tampered)

      rabbitmq = start_fake_rabbitmq()

      assert :invalid_signature =
               Consumer.handle_message("promocao.publicada", json, keys, rabbitmq)

      refute_received {:published, _, _}
    end

    test "descarta evento assinado por chave desconhecida", %{keys: keys} do
      {outra_priv, _} = Crypto.generate_key_pair()

      original =
        Event.new("promocao.publicada", %{"categoria" => "livro"}, "promocao")
        |> Event.sign(outra_priv)

      {:ok, json} = Event.Envelope.encode(original)

      rabbitmq = start_fake_rabbitmq()

      assert :invalid_signature =
               Consumer.handle_message("promocao.publicada", json, keys, rabbitmq)

      refute_received {:published, _, _}
    end

    test "descarta promocao.destaque assinada com chave do promocao", %{
      promocao_priv: promocao_priv,
      keys: keys
    } do
      original =
        Event.new("promocao.destaque", %{"categoria" => "livro"}, "ranking")
        |> Event.sign(promocao_priv)

      {:ok, json} = Event.Envelope.encode(original)

      rabbitmq = start_fake_rabbitmq()

      assert :invalid_signature =
               Consumer.handle_message("promocao.destaque", json, keys, rabbitmq)

      refute_received {:published, _, _}
    end

    test "descarta routing key desconhecida", %{promocao_priv: promocao_priv, keys: keys} do
      original =
        Event.new("promocao.recebida", %{"categoria" => "livro"}, "gateway")
        |> Event.sign(promocao_priv)

      {:ok, json} = Event.Envelope.encode(original)

      rabbitmq = start_fake_rabbitmq()

      assert :unknown_routing_key =
               Consumer.handle_message("promocao.recebida", json, keys, rabbitmq)

      refute_received {:published, _, _}
    end

    test "descarta evento sem categoria", %{promocao_priv: promocao_priv, keys: keys} do
      original =
        Event.new("promocao.publicada", %{"nome" => "X"}, "promocao")
        |> Event.sign(promocao_priv)

      {:ok, json} = Event.Envelope.encode(original)

      rabbitmq = start_fake_rabbitmq()

      assert :missing_categoria =
               Consumer.handle_message("promocao.publicada", json, keys, rabbitmq)

      refute_received {:published, _, _}
    end

    test "retorna erro para JSON invalido", %{keys: keys} do
      rabbitmq = start_fake_rabbitmq()

      assert {:error, _} =
               Consumer.handle_message("promocao.publicada", "isso nao e json", keys, rabbitmq)

      refute_received {:published, _, _}
    end
  end

  # --- Helpers ---

  # Inicia um GenServer "fake" que captura chamadas de publish
  # e envia para o processo de teste via send/2
  defmodule FakeRabbitMQ do
    @moduledoc false
    use GenServer

    @impl true
    def init(test_pid), do: {:ok, test_pid}

    @impl true
    def handle_call({:publish, routing_key, payload}, _from, test_pid) do
      send(test_pid, {:published, routing_key, payload})
      {:reply, :ok, test_pid}
    end
  end

  defp start_fake_rabbitmq do
    {:ok, pid} = GenServer.start_link(FakeRabbitMQ, self())
    pid
  end
end
