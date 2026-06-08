defmodule Notificacao.Consumer do
  @moduledoc """
  Consumidor de eventos `promocao.publicada` e `promocao.categoria.destaque` do MS Notificacao.

  Para cada evento recebido:

  1. Decodifica o envelope JSON
  2. Verifica a assinatura digital usando a chave publica do produtor
     (`promocao` para `promocao.publicada`; `ranking` para `promocao.categoria.destaque`)
  3. Extrai a `categoria` do payload
  4. Constroi um novo evento `Shared.Event` assinado com a chave privada do
     proprio MS Notificacao, contendo os dados da promocao e um campo `tipo`:
     - `"nova"` para `promocao.publicada`
     - `"hot deal"` para `promocao.categoria.destaque` (literal, conforme enunciado)
  5. Publica a notificacao na routing key `promocao.categoria.<categoria>`

  Eventos com assinatura invalida sao descartados (logados como warning).

  ## Fluxo

      MS Promocao --[promocao.publicada]----------> RabbitMQ --> Consumer
      MS Ranking  --[promocao.categoria.destaque]-> RabbitMQ --> Consumer
                                                                    │
                                                                    ├── valida assinatura
                                                                    │
                                                                    └── se valido:
                                                                         └─[promocao.categoria.<categoria>]--> RabbitMQ
                                                                               (envelope Shared.Event assinado)

  ## Decisoes de design

  - **Notificacao assina suas mensagens**: as notificacoes publicadas sao
    envelopes `Shared.Event` assinados com a chave privada do MS Notificacao,
    no mesmo formato dos demais eventos do sistema. Isso padroniza o formato
    de fio e permite ao consumidor verificar autenticidade e integridade.

  - **Palavra "hot deal" literal**: para `promocao.categoria.destaque`, a notificacao
    contem o campo `"tipo": "hot deal"` exatamente como pedido pelo
    enunciado ("publicar um novo evento na categoria correspondente com
    a palavra 'hot deal'").

  - **Stateless**: as chaves publicas sao carregadas uma vez no `start/1`
    e capturadas via closure no callback.
  """

  require Logger

  alias Shared.Crypto
  alias Shared.Event
  alias Shared.Event.Envelope
  alias Shared.RabbitMQ

  @tipo_nova "nova"
  @tipo_hot_deal "hot deal"
  @service_name "notificacao"

  @doc """
  Inicia o consumidor: carrega chaves publicas e registra callback no RabbitMQ.

  Deve ser chamado uma vez no startup do aplicativo, depois de o
  `Shared.RabbitMQ` ja estar rodando.

  ## Exemplo

      Notificacao.Consumer.start(:notificacao_rabbitmq)
  """
  @spec start(GenServer.server()) :: :ok
  def start(rabbitmq_server) do
    {:ok, promocao_pub} = Crypto.load_public_key("promocao")
    {:ok, ranking_pub} = Crypto.load_public_key("ranking")
    {:ok, private_key} = Crypto.load_private_key(@service_name)

    keys = %{
      "promocao.publicada" => {promocao_pub, @tipo_nova},
      "promocao.categoria.destaque" => {ranking_pub, @tipo_hot_deal}
    }

    RabbitMQ.subscribe(rabbitmq_server, fn routing_key, payload ->
      handle_message(routing_key, payload, keys, rabbitmq_server, private_key)
    end)
  end

  @doc """
  Processa uma mensagem recebida do RabbitMQ.

  Decodifica o envelope, escolhe a chave publica e o tipo da notificacao
  conforme o `routing_key`, valida a assinatura e (se valida) publica
  um envelope `Shared.Event` assinado em `promocao.categoria.<categoria>`.

  ## Retornos

  - `:ok` — evento processado e notificacao publicada
  - `:invalid_signature` — assinatura invalida, descartado
  - `:unknown_routing_key` — routing key nao reconhecida, descartado
  - `:missing_categoria` — payload sem campo `categoria`, descartado
  - `{:error, reason}` — falha ao decodificar/codificar o envelope/notificacao
  """
  @spec handle_message(
          String.t(),
          binary(),
          %{String.t() => {Crypto.public_key(), String.t()}},
          GenServer.server(),
          Crypto.private_key()
        ) ::
          :ok | :invalid_signature | :unknown_routing_key | :missing_categoria | {:error, term()}
  def handle_message(routing_key, payload, keys, rabbitmq, private_key) do
    with {:ok, {public_key, tipo}} <- fetch_key(keys, routing_key),
         {:ok, event} <- Envelope.decode(payload),
         true <- Event.verify(event, public_key),
         {:ok, categoria} <- fetch_categoria(event),
         {:ok, json} <- build_notificacao(tipo, categoria, event, private_key) do
      RabbitMQ.publish(rabbitmq, "promocao.categoria.#{categoria}", json)
    else
      :unknown_routing_key ->
        Logger.warning("Routing key desconhecida: #{routing_key}, descartando evento")
        :unknown_routing_key

      false ->
        Logger.warning("Assinatura invalida em #{routing_key}, descartando evento")
        :invalid_signature

      :missing_categoria ->
        Logger.warning("Evento sem categoria, descartando")
        :missing_categoria

      {:error, reason} ->
        Logger.warning("Payload invalido, descartando evento: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_key(keys, routing_key) do
    case Map.fetch(keys, routing_key) do
      {:ok, value} -> {:ok, value}
      :error -> :unknown_routing_key
    end
  end

  defp fetch_categoria(%Event{payload: %{"categoria" => categoria}})
       when is_binary(categoria) and categoria != "" do
    {:ok, categoria}
  end

  defp fetch_categoria(_event), do: :missing_categoria

  defp build_notificacao(tipo, categoria, %Event{} = event, private_key) do
    Event.new(
      "promocao.categoria.#{categoria}",
      %{
        "tipo" => tipo,
        "categoria" => categoria,
        "promo_id" => event.id,
        "promo" => event.payload
      },
      @service_name
    )
    |> Event.sign(private_key)
    |> Envelope.encode()
  end
end
