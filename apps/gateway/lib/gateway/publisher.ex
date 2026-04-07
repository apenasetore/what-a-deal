defmodule Gateway.Publisher do
  @moduledoc """
  Publica eventos assinados no RabbitMQ.

  Responsavel por criar eventos `promocao.recebida` (cadastro de promocao)
  e `promocao.voto` (votacao), assina-los com a chave privada do Gateway
  e publicar no exchange via Shared.RabbitMQ.
  """

  alias Shared.{Crypto, Event, Event.Envelope}

  require Logger

  @service_name "gateway"

  @spec publish_promocao(map()) :: :ok | {:error, term()}
  def publish_promocao(promo_data) do
    with {:ok, private_key} <- Crypto.load_private_key(@service_name),
         event <- Event.new("promocao.recebida", promo_data, @service_name),
         signed <- Event.sign(event, private_key),
         {:ok, json} <- Envelope.encode(signed) do
      Logger.info("Publicando promocao.recebida: #{promo_data["nome"]}")
      Shared.RabbitMQ.publish(:gateway_rabbitmq, "promocao.recebida", json)
    end
  end

  @spec publish_voto(String.t(), integer()) :: :ok | {:error, term()}
  def publish_voto(promo_id, voto) do
    with {:ok, private_key} <- Crypto.load_private_key(@service_name),
         payload <- %{"promo_id" => promo_id, "voto" => voto},
         event <- Event.new("promocao.voto", payload, @service_name),
         signed <- Event.sign(event, private_key),
         {:ok, json} <- Envelope.encode(signed) do
      Logger.info("Publicando promocao.voto: promo=#{promo_id} voto=#{voto}")
      Shared.RabbitMQ.publish(:gateway_rabbitmq, "promocao.voto", json)
    end
  end
end
