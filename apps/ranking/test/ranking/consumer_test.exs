defmodule Ranking.ConsumerTest do
  # async: false porque VoteStore e um Agent global compartilhado entre testes
  use ExUnit.Case, async: false

  alias Ranking.Consumer
  alias Ranking.VoteStore
  alias Shared.Crypto
  alias Shared.Event
  alias Shared.Event.Envelope

  @threshold 3

  setup do
    ensure_ranking_keys!()
    start_supervised!(VoteStore)

    {gateway_priv, gateway_pub} = Crypto.generate_key_pair()
    rabbitmq = start_fake_rabbitmq()

    %{
      gateway_priv: gateway_priv,
      gateway_pub: gateway_pub,
      rabbitmq: rabbitmq,
      promo_id: unique_id()
    }
  end

  describe "handle_message/4 — voto valido" do
    test "registra voto e retorna :ok", ctx do
      json = signed_voto(ctx.promo_id, 1, ctx.gateway_priv)

      assert :ok = Consumer.handle_message("promocao.voto", json, ctx.gateway_pub, ctx.rabbitmq)
    end

    test "voto isolado nao publica destaque", ctx do
      json = signed_voto(ctx.promo_id, 1, ctx.gateway_priv)

      Consumer.handle_message("promocao.voto", json, ctx.gateway_pub, ctx.rabbitmq)

      refute_received {:published, "promocao.destaque", _}
    end

    test "publica destaque quando score atinge threshold", ctx do
      for _ <- 1..@threshold do
        json = signed_voto(ctx.promo_id, 1, ctx.gateway_priv)
        Consumer.handle_message("promocao.voto", json, ctx.gateway_pub, ctx.rabbitmq)
      end

      assert_received {:published, "promocao.destaque", payload}

      {:ok, event} = Envelope.decode(payload)
      assert event.type == "promocao.destaque"
      assert event.source == "ranking"
      assert event.payload["id"] == ctx.promo_id
    end

    test "destaque publicado contem dados completos da promo", ctx do
      promo = %{
        "id" => ctx.promo_id,
        "nome" => "Clean Code",
        "categoria" => "livro",
        "loja" => "Amazon",
        "preco_original" => 89.90,
        "preco_promocional" => 45.00
      }

      for _ <- 1..@threshold do
        json = signed_voto_with_promo(promo, 1, ctx.gateway_priv)
        Consumer.handle_message("promocao.voto", json, ctx.gateway_pub, ctx.rabbitmq)
      end

      assert_received {:published, "promocao.destaque", payload}
      {:ok, event} = Envelope.decode(payload)

      assert event.payload["nome"] == "Clean Code"
      assert event.payload["categoria"] == "livro"
      assert event.payload["loja"] == "Amazon"
    end

    test "destaque assinado pela chave privada do ranking", ctx do
      for _ <- 1..@threshold do
        json = signed_voto(ctx.promo_id, 1, ctx.gateway_priv)
        Consumer.handle_message("promocao.voto", json, ctx.gateway_pub, ctx.rabbitmq)
      end

      assert_received {:published, "promocao.destaque", payload}
      {:ok, event} = Envelope.decode(payload)

      {:ok, ranking_pub} = Crypto.load_public_key("ranking")
      assert Event.verify(event, ranking_pub)
    end

    test "nao publica destaque duplicado quando promo ja marcada", ctx do
      # Cruza o threshold pela primeira vez
      for _ <- 1..@threshold do
        json = signed_voto(ctx.promo_id, 1, ctx.gateway_priv)
        Consumer.handle_message("promocao.voto", json, ctx.gateway_pub, ctx.rabbitmq)
      end

      assert_received {:published, "promocao.destaque", _}

      # Mais um voto positivo nao deve publicar de novo
      json = signed_voto(ctx.promo_id, 1, ctx.gateway_priv)
      Consumer.handle_message("promocao.voto", json, ctx.gateway_pub, ctx.rabbitmq)

      refute_received {:published, "promocao.destaque", _}
    end

    test "votos negativos abaixam o score e nao destacam", ctx do
      json_pos = signed_voto(ctx.promo_id, 1, ctx.gateway_priv)
      json_neg = signed_voto(ctx.promo_id, -1, ctx.gateway_priv)

      Consumer.handle_message("promocao.voto", json_pos, ctx.gateway_pub, ctx.rabbitmq)
      Consumer.handle_message("promocao.voto", json_pos, ctx.gateway_pub, ctx.rabbitmq)
      Consumer.handle_message("promocao.voto", json_neg, ctx.gateway_pub, ctx.rabbitmq)
      Consumer.handle_message("promocao.voto", json_pos, ctx.gateway_pub, ctx.rabbitmq)

      # score = 2 -1 + 1 = 2, abaixo do threshold de 3
      refute_received {:published, "promocao.destaque", _}
    end
  end

  describe "handle_message/4 — voto invalido (caminho de seguranca)" do
    test "descarta voto com payload adulterado apos assinatura", ctx do
      original = Event.new("promocao.voto", %{"promo_id" => ctx.promo_id, "voto" => 1}, "gateway")
      signed = Event.sign(original, ctx.gateway_priv)
      tampered = %{signed | payload: %{"promo_id" => ctx.promo_id, "voto" => 100}}
      {:ok, json} = Envelope.encode(tampered)

      assert :invalid_signature =
               Consumer.handle_message("promocao.voto", json, ctx.gateway_pub, ctx.rabbitmq)

      refute_received {:published, _, _}
    end

    test "descarta voto assinado por chave desconhecida", ctx do
      {outra_priv, _} = Crypto.generate_key_pair()
      json = signed_voto(ctx.promo_id, 1, outra_priv)

      assert :invalid_signature =
               Consumer.handle_message("promocao.voto", json, ctx.gateway_pub, ctx.rabbitmq)

      refute_received {:published, _, _}
    end

    test "voto invalido nao incrementa o VoteStore", ctx do
      {outra_priv, _} = Crypto.generate_key_pair()
      json = signed_voto(ctx.promo_id, 1, outra_priv)

      Consumer.handle_message("promocao.voto", json, ctx.gateway_pub, ctx.rabbitmq)

      # Score deveria continuar 0 — vote retorna o score atualizado
      assert VoteStore.vote(ctx.promo_id, 0) == 0
    end

    test "retorna erro para JSON corrompido", ctx do
      assert {:error, _} =
               Consumer.handle_message("promocao.voto", "lixo", ctx.gateway_pub, ctx.rabbitmq)

      refute_received {:published, _, _}
    end

    test "retorna erro para envelope com Base64 invalido", ctx do
      json =
        Jason.encode!(%{
          "id" => "abc",
          "type" => "promocao.voto",
          "payload" => %{},
          "source" => "gateway",
          "signature" => "!!!nao-e-base64!!!",
          "timestamp" => DateTime.to_iso8601(DateTime.utc_now())
        })

      assert {:error, _} =
               Consumer.handle_message("promocao.voto", json, ctx.gateway_pub, ctx.rabbitmq)

      refute_received {:published, _, _}
    end
  end

  # --- Helpers ---

  defp signed_voto(promo_id, voto, gateway_priv) do
    promo = %{"id" => promo_id, "nome" => "Test", "categoria" => "livro"}
    signed_voto_with_promo(promo, voto, gateway_priv)
  end

  defp signed_voto_with_promo(%{"id" => promo_id} = promo, voto, gateway_priv) do
    payload = %{"promo_id" => promo_id, "voto" => voto, "promo" => promo}

    Event.new("promocao.voto", payload, "gateway")
    |> Event.sign(gateway_priv)
    |> Envelope.encode()
    |> elem(1)
  end

  defp unique_id do
    "promo_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
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

  # Fake RabbitMQ que captura publishes via send para o processo de teste.
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
