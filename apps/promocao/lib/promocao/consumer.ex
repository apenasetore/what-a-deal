defmodule Promocao.Consumer do
  @moduledoc """
  Consumidor de eventos `promocao.recebida` do MS Promocao.

  Recebe eventos publicados pelo Gateway, valida a assinatura digital
  com a chave publica do Gateway, e republica o evento como
  `promocao.publicada` assinado com a chave privada do Promocao.

  Eventos com assinatura invalida sao descartados (logados como warning).

  ## Fluxo

      Gateway --[promocao.recebida]--> RabbitMQ --> Consumer
                                                       │
                                                       ├── valida assinatura
                                                       │
                                                       └── se valido:
                                                            └─[promocao.publicada]--> RabbitMQ

  ## Decisoes de design

  - **Sem state proprio**: o Consumer e stateless. Chaves sao carregadas
    uma vez no `start/1` e capturadas via closure no callback.

  - **Novo evento, nao reembrulhar**: o evento republicado tem novo `id`,
    `timestamp` e `source`. Compartilha apenas o `payload` com o original.

  - **Sem persistencia**: nao mantem store de promocoes. Quem persiste
    a lista de promocoes validadas e o Gateway, ao consumir
    `promocao.publicada`.
  """

  require Logger

  alias Shared.Crypto
  alias Shared.Event
  alias Shared.RabbitMQ

  @doc """
  Inicia o consumidor: carrega chaves e registra callback no RabbitMQ.

  Deve ser chamado uma vez no startup do aplicativo, depois de o
  `Shared.RabbitMQ` ja estar rodando.

  ## Exemplo

      Promocao.Consumer.start(:promocao_rabbitmq)
  """
  @spec start(GenServer.server()) :: :ok
  def start(rabbitmq_server) do
    {:ok, promocao_priv} = Crypto.load_private_key("promocao")
    {:ok, gateway_pub} = Crypto.load_public_key("gateway")

    RabbitMQ.subscribe(rabbitmq_server, fn routing_key, payload ->
      handle_message(routing_key, payload, gateway_pub, promocao_priv, rabbitmq_server)
    end)
  end

  @doc """
  Processa uma mensagem recebida do RabbitMQ.

  Decodifica o envelope, valida a assinatura com a chave publica do
  Gateway. Se valido, cria um novo evento `promocao.publicada` assinado
  com a chave privada do Promocao e publica via `rabbitmq`.

  ## Retornos

  - `:ok` — evento processado e republicado com sucesso
  - `:invalid_signature` — assinatura invalida, evento descartado
  - `{:error, reason}` — falha ao decodificar o envelope
  """
  @spec handle_message(
          String.t(),
          binary(),
          Crypto.public_key(),
          Crypto.private_key(),
          GenServer.server()
        ) :: :ok | :invalid_signature | {:error, term()}
  def handle_message(_routing_key, payload, gateway_pub, promocao_priv, rabbitmq) do
    with {:ok, event} <- Event.Envelope.decode(payload),
         true <- Event.verify(event, gateway_pub) do
      new_event =
        Event.new("promocao.publicada", event.payload, "promocao") |> Event.sign(promocao_priv)

      {:ok, json} = Event.Envelope.encode(new_event)
      RabbitMQ.publish(rabbitmq, "promocao.publicada", json)
    else
      false ->
        Logger.warning("Assinatura invalida, descartando evento")
        :invalid_signature

      {:error, reason} ->
        Logger.warning("Payload invalido, descartando evento")
        {:error, reason}
    end
  end
end
