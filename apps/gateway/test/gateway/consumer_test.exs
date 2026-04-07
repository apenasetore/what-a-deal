defmodule Gateway.ConsumerTest do
  use ExUnit.Case

  @moduletag :integration

  alias Shared.{Crypto, Event, Event.Envelope}

  describe "consome promocao.publicada" do
    setup do
      start_supervised!(Gateway.PromoStore)

      # Gera chaves do MS Promocao (quem assina promocao.publicada)
      {priv, pub} = Crypto.generate_key_pair()
      Crypto.save_keys("promocao", priv, pub)

      fila = "test_consumer_#{System.unique_integer([:positive])}"

      {:ok, rabbitmq} =
        Shared.RabbitMQ.start_link(
          name: :gateway_rabbitmq,
          url: rabbitmq_url(),
          queues: [{fila, ["promocao.publicada"]}],
          queue_opts: [auto_delete: true]
        )

      {:ok, consumer} = Gateway.Consumer.start_link([])

      # Aguarda subscribe
      Process.sleep(1_000)

      on_exit(fn ->
        if Process.alive?(consumer), do: GenServer.stop(consumer)
        if Process.alive?(rabbitmq), do: GenServer.stop(rabbitmq)
      end)

      %{private_key: priv, public_key: pub}
    end

    test "armazena promocao com assinatura valida", %{private_key: priv} do
      promo_data = %{
        "id" => "promo-001",
        "nome" => "Clean Code",
        "categoria" => "livro",
        "preco_original" => 89.90,
        "preco_promocional" => 45.00,
        "loja" => "Amazon"
      }

      event =
        Event.new("promocao.publicada", promo_data, "promocao")
        |> Event.sign(priv)

      {:ok, json} = Envelope.encode(event)
      :ok = Shared.RabbitMQ.publish(:gateway_rabbitmq, "promocao.publicada", json)

      # Aguarda processamento
      Process.sleep(2_000)

      assert Gateway.PromoStore.count() == 1
      stored = Gateway.PromoStore.get("promo-001")
      assert stored["nome"] == "Clean Code"
      assert stored["categoria"] == "livro"
    end

    test "descarta evento com assinatura invalida" do
      # Gera chaves diferentes (simulando assinatura invalida)
      {other_priv, _other_pub} = Crypto.generate_key_pair()

      promo_data = %{
        "id" => "promo-fake",
        "nome" => "Fake Promo"
      }

      event =
        Event.new("promocao.publicada", promo_data, "promocao")
        |> Event.sign(other_priv)

      {:ok, json} = Envelope.encode(event)
      :ok = Shared.RabbitMQ.publish(:gateway_rabbitmq, "promocao.publicada", json)

      Process.sleep(2_000)

      assert Gateway.PromoStore.count() == 0
    end
  end

  defp rabbitmq_url do
    System.get_env("RABBITMQ_URL", "amqp://guest:guest@localhost")
  end
end
