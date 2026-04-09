defmodule Ranking.PublisherTest do
  use ExUnit.Case, async: true

  alias Ranking.Publisher
  alias Shared.Crypto
  alias Shared.Event
  alias Shared.Event.Envelope

  setup do
    ensure_ranking_keys!()
    %{rabbitmq: start_fake_rabbitmq()}
  end

  describe "publish_destaque/2" do
    test "publica evento na routing key promocao.destaque", %{rabbitmq: rabbitmq} do
      promo = sample_promo()

      assert :ok = Publisher.publish_destaque(promo, rabbitmq)

      assert_received {:published, "promocao.destaque", _payload}
    end

    test "evento publicado tem type, source e payload corretos", %{rabbitmq: rabbitmq} do
      promo = sample_promo()
      Publisher.publish_destaque(promo, rabbitmq)

      assert_received {:published, "promocao.destaque", payload}
      {:ok, event} = Envelope.decode(payload)

      assert event.type == "promocao.destaque"
      assert event.source == "ranking"
      assert event.payload == promo
    end

    test "evento e assinado pela chave privada do ranking", %{rabbitmq: rabbitmq} do
      Publisher.publish_destaque(sample_promo(), rabbitmq)

      assert_received {:published, "promocao.destaque", payload}
      {:ok, event} = Envelope.decode(payload)

      {:ok, ranking_pub} = Crypto.load_public_key("ranking")
      assert Event.verify(event, ranking_pub)
    end

    test "evento tem id unico por chamada", %{rabbitmq: rabbitmq} do
      promo = sample_promo()

      Publisher.publish_destaque(promo, rabbitmq)
      Publisher.publish_destaque(promo, rabbitmq)

      assert_received {:published, _, payload1}
      assert_received {:published, _, payload2}

      {:ok, e1} = Envelope.decode(payload1)
      {:ok, e2} = Envelope.decode(payload2)

      assert e1.id != e2.id
    end
  end

  # --- Helpers ---

  defp sample_promo do
    %{
      "id" => "promo-42",
      "nome" => "Clean Code",
      "categoria" => "livro",
      "loja" => "Amazon",
      "preco_original" => 89.90,
      "preco_promocional" => 45.00
    }
  end

  defp ensure_ranking_keys! do
    case Crypto.load_private_key("ranking") do
      {:ok, _} ->
        :ok

      {:error, _} ->
        {priv, pub} = Crypto.generate_key_pair()
        Crypto.save_keys("ranking", priv, pub)
    end
  end

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
