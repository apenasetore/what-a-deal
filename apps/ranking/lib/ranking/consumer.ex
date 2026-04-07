defmodule Ranking.Consumer do
  @moduledoc """
  Consumidor de eventos `promocao.voto` do MS Ranking.

  Recebe votos publicados pelo Gateway, valida a assinatura digital,
  registra o voto no VoteStore e, se o score atingir o threshold,
  publica `promocao.destaque` via Ranking.Publisher.

  ## Fluxo

      Gateway --[promocao.voto]--> RabbitMQ --> Consumer
                                                   |
                                                   +-- valida assinatura
                                                   |
                                                   +-- registra voto no VoteStore
                                                   |
                                                   +-- se score >= threshold:
                                                        +--[promocao.destaque]--> RabbitMQ
  """

  require Logger

  alias Shared.{Crypto, Event, RabbitMQ}

  @destaque_threshold 3

  @doc """
  Inicia o consumidor: carrega chaves e registra callback no RabbitMQ.

  Deve ser chamado apos o Shared.RabbitMQ estar rodando.
  """
  @spec start(GenServer.server()) :: :ok
  def start(rabbitmq_server) do
    {:ok, gateway_pub} = Crypto.load_public_key("gateway")

    RabbitMQ.subscribe(rabbitmq_server, fn routing_key, payload ->
      handle_message(routing_key, payload, gateway_pub, rabbitmq_server)
    end)
  end

  @doc """
  Processa uma mensagem `promocao.voto`.

  Valida assinatura, registra voto, verifica threshold para destaque.
  """
  @spec handle_message(String.t(), binary(), term(), GenServer.server()) ::
          :ok | :invalid_signature | {:error, term()}
  def handle_message(_routing_key, payload, gateway_pub, rabbitmq) do
    with {:ok, event} <- Event.Envelope.decode(payload),
         true <- Event.verify(event, gateway_pub) do
      promo_id = event.payload["promo_id"]
      voto = event.payload["voto"]
      promo = event.payload["promo"]

      score = Ranking.VoteStore.vote(promo_id, voto)
      Logger.info("Voto registrado: promo=#{promo_id} voto=#{voto} score=#{score}")

      if score >= @destaque_threshold and not Ranking.VoteStore.destaque?(promo_id) do
        Ranking.VoteStore.marcar_destaque(promo_id)
        Ranking.Publisher.publish_destaque(promo, rabbitmq)
      end

      :ok
    else
      false ->
        Logger.warning("Assinatura invalida, descartando evento")
        :invalid_signature

      {:error, reason} ->
        Logger.error("Erro ao processar mensagem: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
