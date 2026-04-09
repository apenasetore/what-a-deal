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

  @doc """
  Publica uma promocao assinada com chave RSA falsa.

  Serve para demonstrar que o MS Promocao descarta eventos com
  assinatura invalida. Basta chamar no iex:

      Gateway.Publisher.publish_fake_promocao()
  """
  @spec publish_fake_promocao() :: :ok | {:error, term()}
  def publish_fake_promocao do
    {fake_key, _} = Crypto.generate_key_pair()

    payload = %{
      "nome" => "Produto Falso",
      "descricao" => "Evento com assinatura invalida",
      "preco_original" => 100.0,
      "preco_promocional" => 1.0,
      "categoria" => "livro",
      "loja" => "Loja Fantasma"
    }

    event = Event.new("promocao.recebida", payload, @service_name)
    signed = Event.sign(event, fake_key)
    {:ok, json} = Event.Envelope.encode(signed)

    Logger.warning("Publicando promocao.recebida com assinatura FALSA")
    Shared.RabbitMQ.publish(:gateway_rabbitmq, "promocao.recebida", json)
  end

  @doc """
  Publica um voto assinado com chave RSA falsa.

  Serve para demonstrar que o MS Ranking descarta eventos com
  assinatura invalida. Basta chamar no iex:

      Gateway.Publisher.publish_fake_voto()
  """
  @spec publish_fake_voto() :: :ok | {:error, term()}
  def publish_fake_voto do
    {fake_key, _} = Crypto.generate_key_pair()

    payload = %{
      "promo_id" => "fake-id",
      "voto" => 1,
      "promo" => %{"nome" => "Produto Falso", "id" => "fake-id"}
    }

    event = Event.new("promocao.voto", payload, @service_name)
    signed = Event.sign(event, fake_key)
    {:ok, json} = Event.Envelope.encode(signed)

    Logger.warning("Publicando promocao.voto com assinatura FALSA")
    Shared.RabbitMQ.publish(:gateway_rabbitmq, "promocao.voto", json)
  end

  @spec publish_voto(map(), integer()) :: :ok | {:error, term()}
  def publish_voto(promo, voto) do
    promo_id = promo["id"]

    with {:ok, private_key} <- Crypto.load_private_key(@service_name),
         payload <- %{"promo_id" => promo_id, "voto" => voto, "promo" => promo},
         event <- Event.new("promocao.voto", payload, @service_name),
         signed <- Event.sign(event, private_key),
         {:ok, json} <- Envelope.encode(signed) do
      Logger.info("Publicando promocao.voto: promo=#{promo_id} voto=#{voto}")
      Shared.RabbitMQ.publish(:gateway_rabbitmq, "promocao.voto", json)
    end
  end
end
