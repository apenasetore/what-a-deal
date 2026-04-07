defmodule Promocao.ConsumerTest do
  use ExUnit.Case, async: true

  alias Promocao.Consumer
  alias Shared.Crypto
  alias Shared.Event

  describe "handle_message/5 — evento valido" do
    setup do
      {gateway_priv, gateway_pub} = Crypto.generate_key_pair()
      {promocao_priv, promocao_pub} = Crypto.generate_key_pair()

      %{
        gateway_priv: gateway_priv,
        gateway_pub: gateway_pub,
        promocao_priv: promocao_priv,
        promocao_pub: promocao_pub
      }
    end

    test "republica evento como promocao.publicada", %{
      gateway_priv: gateway_priv,
      gateway_pub: gateway_pub,
      promocao_priv: promocao_priv
    } do
      payload = %{"nome" => "Clean Code", "preco" => 45.0, "categoria" => "livro"}

      json =
        Event.new("promocao.recebida", payload, "gateway")
        |> Event.sign(gateway_priv)
        |> Event.Envelope.encode()
        |> elem(1)

      rabbitmq = start_fake_rabbitmq()

      assert :ok =
               Consumer.handle_message(
                 "promocao.recebida",
                 json,
                 gateway_pub,
                 promocao_priv,
                 rabbitmq
               )

      assert_received {:published, "promocao.publicada", published_json}

      {:ok, published_event} = Event.Envelope.decode(published_json)
      assert published_event.type == "promocao.publicada"
      assert published_event.source == "promocao"
      assert published_event.payload == payload
    end

    test "evento republicado tem ID novo", %{
      gateway_priv: gateway_priv,
      gateway_pub: gateway_pub,
      promocao_priv: promocao_priv
    } do
      original = Event.new("promocao.recebida", %{}, "gateway") |> Event.sign(gateway_priv)
      {:ok, json} = Event.Envelope.encode(original)

      rabbitmq = start_fake_rabbitmq()

      Consumer.handle_message("promocao.recebida", json, gateway_pub, promocao_priv, rabbitmq)

      assert_received {:published, _, published_json}
      {:ok, published_event} = Event.Envelope.decode(published_json)

      assert published_event.id != original.id
    end

    test "evento republicado e assinado pela chave do promocao", %{
      gateway_priv: gateway_priv,
      gateway_pub: gateway_pub,
      promocao_priv: promocao_priv,
      promocao_pub: promocao_pub
    } do
      original = Event.new("promocao.recebida", %{}, "gateway") |> Event.sign(gateway_priv)
      {:ok, json} = Event.Envelope.encode(original)

      rabbitmq = start_fake_rabbitmq()

      Consumer.handle_message("promocao.recebida", json, gateway_pub, promocao_priv, rabbitmq)

      assert_received {:published, _, published_json}
      {:ok, published_event} = Event.Envelope.decode(published_json)

      assert Event.verify(published_event, promocao_pub)
    end
  end

  describe "handle_message/5 — evento invalido" do
    setup do
      {gateway_priv, gateway_pub} = Crypto.generate_key_pair()
      {promocao_priv, _promocao_pub} = Crypto.generate_key_pair()

      %{
        gateway_priv: gateway_priv,
        gateway_pub: gateway_pub,
        promocao_priv: promocao_priv
      }
    end

    test "descarta evento com assinatura invalida", %{
      gateway_priv: gateway_priv,
      gateway_pub: gateway_pub,
      promocao_priv: promocao_priv
    } do
      original = Event.new("promocao.recebida", %{"nome" => "X"}, "gateway") |> Event.sign(gateway_priv)

      # Adultera o payload depois da assinatura
      tampered = %{original | payload: %{"nome" => "Y"}}
      {:ok, json} = Event.Envelope.encode(tampered)

      rabbitmq = start_fake_rabbitmq()

      assert :invalid_signature =
               Consumer.handle_message(
                 "promocao.recebida",
                 json,
                 gateway_pub,
                 promocao_priv,
                 rabbitmq
               )

      refute_received {:published, _, _}
    end

    test "descarta evento assinado por chave desconhecida", %{
      gateway_pub: gateway_pub,
      promocao_priv: promocao_priv
    } do
      {outra_priv, _} = Crypto.generate_key_pair()

      original = Event.new("promocao.recebida", %{}, "gateway") |> Event.sign(outra_priv)
      {:ok, json} = Event.Envelope.encode(original)

      rabbitmq = start_fake_rabbitmq()

      assert :invalid_signature =
               Consumer.handle_message(
                 "promocao.recebida",
                 json,
                 gateway_pub,
                 promocao_priv,
                 rabbitmq
               )

      refute_received {:published, _, _}
    end

    test "retorna erro para JSON invalido", %{
      gateway_pub: gateway_pub,
      promocao_priv: promocao_priv
    } do
      rabbitmq = start_fake_rabbitmq()

      assert {:error, _} =
               Consumer.handle_message(
                 "promocao.recebida",
                 "isso nao e json",
                 gateway_pub,
                 promocao_priv,
                 rabbitmq
               )

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
