defmodule Ranking.Publisher do
  @moduledoc """
  Publica eventos `promocao.destaque` no RabbitMQ.

  Quando o score de uma promocao atinge o threshold, assina e publica
  o evento de destaque usando a chave privada do Ranking.
  """

  require Logger

  alias Shared.{Crypto, Event, Event.Envelope, RabbitMQ}

  @service_name "ranking"

  @doc "Publica evento promocao.destaque assinado para a promocao dada."
  @spec publish_destaque(map(), GenServer.server()) :: :ok | {:error, term()}
  def publish_destaque(promo_payload, rabbitmq) do
    with {:ok, private_key} <- Crypto.load_private_key(@service_name),
         event <- Event.new("promocao.categoria.destaque", promo_payload, @service_name),
         signed <- Event.sign(event, private_key),
         {:ok, json} <- Envelope.encode(signed) do
      Logger.info("Publicando promocao.categoria.destaque: promo=#{promo_payload["id"]}")
      RabbitMQ.publish(rabbitmq, "promocao.categoria.destaque", json)
    end
  end
end
