defmodule Notificacao.Consumer do
  @moduledoc """
  Consumidor de eventos `promocao.publicada` e `promocao.destaque` do MS Notificacao.

  Para cada evento recebido:

  1. Decodifica o envelope JSON
  2. Verifica a assinatura digital usando a chave publica do produtor
     (`promocao` para `promocao.publicada`; `ranking` para `promocao.destaque`)
  3. Extrai a `categoria` do payload
  4. Constroi uma notificacao JSON nova (NAO assinada) contendo os dados
     da promocao e um campo `tipo`:
     - `"nova"` para `promocao.publicada`
     - `"hot deal"` para `promocao.destaque` (literal, conforme enunciado)
  5. Publica a notificacao na routing key `promocao.<categoria>`

  Eventos com assinatura invalida sao descartados (logados como warning).

  ## Fluxo

      MS Promocao --[promocao.publicada]--> RabbitMQ --> Consumer
      MS Ranking  --[promocao.destaque]---> RabbitMQ --> Consumer
                                                            │
                                                            ├── valida assinatura
                                                            │
                                                            └── se valido:
                                                                 └─[promocao.<categoria>]--> RabbitMQ
                                                                       (notificacao JSON nao assinada)

  ## Decisoes de design

  - **Notificacao nao assina**: o enunciado dispensa explicitamente o MS
    Notificacao do requisito de assinatura digital. As notificacoes
    publicadas sao mensagens JSON simples, nao envelopes `Shared.Event`.

  - **Palavra "hot deal" literal**: para `promocao.destaque`, a notificacao
    contem o campo `"tipo": "hot deal"` exatamente como pedido pelo
    enunciado ("publicar um novo evento na categoria correspondente com
    a palavra 'hot deal'").

  - **Stateless**: as chaves publicas sao carregadas uma vez no `start/1`
    e capturadas via closure no callback.
  """

  require Logger

  import Swoosh.Email

  alias Shared.Crypto
  alias Shared.Event
  alias Shared.Event.Envelope
  alias Shared.RabbitMQ

  @tipo_nova "nova"
  @tipo_hot_deal "hot deal"

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

    keys = %{
      "promocao.publicada" => {promocao_pub, @tipo_nova},
      "promocao.categoria.destaque" => {ranking_pub, @tipo_hot_deal}
    }

    RabbitMQ.subscribe(rabbitmq_server, fn routing_key, payload ->
      handle_message(routing_key, payload, keys, rabbitmq_server)
    end)
  end

  @doc """
  Processa uma mensagem recebida do RabbitMQ.

  Decodifica o envelope, escolhe a chave publica e o tipo da notificacao
  conforme o `routing_key`, valida a assinatura e (se valida) publica
  uma notificacao JSON em `promocao.<categoria>`.

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
          GenServer.server()
        ) ::
          :ok | :invalid_signature | :unknown_routing_key | :missing_categoria | {:error, term()}


  def handle_message(routing_key, payload, keys, rabbitmq) do
    with {:ok, {public_key, tipo}} <- fetch_key(keys, routing_key),
         {:ok, event} <- Envelope.decode(payload),
         true <- Event.verify(event, public_key),
         {:ok, categoria} <- fetch_categoria(event),
         {:ok, json} <- build_notificacao(tipo, categoria, event) do
      RabbitMQ.publish(rabbitmq, "promocao.categoria.#{categoria}", json)
      if tipo == "hot deal" do
        enviar_email_hot_deal(categoria, event)
      else
        enviar_email_aprovada(categoria, event)
        Logger.info("Notificacao de nova promocao publicada para categoria #{categoria}")
      end
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

  defp build_notificacao(tipo, categoria, %Event{} = event) do
    %{
      "tipo" => tipo,
      "categoria" => categoria,
      "promo_id" => event.id,
      "source" => event.source,
      "timestamp" => DateTime.to_iso8601(event.timestamp),
      "promo" => event.payload
    }
    |> Jason.encode()
  end


  defp enviar_email_aprovada(categoria, %Event{payload: payload}) do
    destino = payload["email"]

    new()
    |> to({payload["loja"] || "", destino})
    |> from({"What a Deal", System.get_env("GMAIL_USER") || "no-reply@whatadeal"})
    |> subject("Sua promocao foi publicada!")
    |> text_body(
      "A promocao \"#{payload["nome"]}\" foi publicada na categoria #{categoria} e ja esta disponivel para os clientes."
    )
    |> Notificacao.Mailer.deliver()
    |> case do
      {:ok, _} ->
        Logger.info("Email de aprovacao enviado para #{destino} (categoria #{categoria})")

      {:error, reason} ->
        Logger.error("Falha ao enviar email de aprovacao para #{destino}: #{inspect(reason)}")
    end
  end
  # Envia o email de hot deal para a empresa que publicou a promocao. O
  # destinatario vem do campo `email` do payload. Falhas sao apenas logadas —
  # nao derrubam o processamento do evento.
  defp enviar_email_hot_deal(categoria, %Event{payload: payload}) do
    destino = payload["email"]

    new()
    |> to({payload["loja"] || "", destino})
    |> from({"What a Deal", System.get_env("GMAIL_USER") || "no-reply@whatadeal"})
    |> subject("Sua promocao virou Hot Deal!")
    |> text_body(
      "A promocao \"#{payload["nome"]}\" entrou em destaque na categoria #{categoria}."
    )
    |> Notificacao.Mailer.deliver()
    |> case do
      {:ok, _} ->
        Logger.info("Email hot deal enviado para #{destino} (categoria #{categoria})")

      {:error, reason} ->
        Logger.error("Falha ao enviar email hot deal para #{destino}: #{inspect(reason)}")
    end
  end
end
