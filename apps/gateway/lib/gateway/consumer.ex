defmodule Gateway.Consumer do
  @moduledoc """
  Consome eventos do RabbitMQ para o Gateway:

  - `promocao.publicada` — verifica a assinatura com a chave publica do MS
    Promocao e, se valida, armazena a promocao no DealStore local.

  - `promocao.categoria.<categoria>` — notificacoes assinadas pelo MS
    Notificacao. Verifica a assinatura com a chave publica do `notificacao`,
    extrai a `categoria` do payload e encaminha o conteudo aos clientes SSE
    inscritos naquela categoria. Quando a notificacao e um hot deal
    (`tipo: "hot deal"`), tambem encaminha para os inscritos na categoria
    especial `"destaque"`.

  Eventos com assinatura invalida sao descartados com log de warning.
  """

  use GenServer

  require Logger

  alias Shared.{Crypto, Event, Event.Envelope}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Process.send_after(self(), :subscribe, 500)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:subscribe, state) do
    Shared.RabbitMQ.subscribe(:gateway_rabbitmq, fn routing_key, payload ->
      handle_message(routing_key, payload)
    end)

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp handle_message("promocao.publicada", payload) do
    with {:ok, event} <- Envelope.decode(payload),
         {:ok, public_key} <- Crypto.load_public_key("promocao"),
         true <- Event.verify(event, public_key) do
      promo = Map.put(event.payload, "id", event.payload["id"] || event.id)
      Gateway.DealStore.add(promo)
      Logger.info("Promocao validada recebida: #{promo["nome"]}")
    else
      false ->
        Logger.warning("Assinatura invalida em promocao.publicada — evento descartado")

      {:error, reason} ->
        Logger.error("Erro ao processar promocao.publicada: #{inspect(reason)}")
    end
  end

  defp handle_message("promocao.categoria." <> rest, payload) do
    Logger.info("[SSE] mensagem RabbitMQ recebida routing_key=promocao.categoria.#{rest}")

    with {:ok, event} <- Envelope.decode(payload),
         {:ok, public_key} <- Crypto.load_public_key("notificacao"),
         true <- Event.verify(event, public_key),
         %{"categoria" => categoria} <- event.payload,
         {:ok, sse_json} <- build_sse_payload(event) do
      Logger.info("[SSE] decodificado categoria=#{categoria}, chamando SSERegistry.notify")
      Gateway.SSERegistry.notify(categoria, sse_json)

      # Hot deals tambem vao para quem segue a categoria especial "destaque",
      # independente da categoria real da promocao.
      if event.payload["tipo"] == "hot deal" and categoria != "destaque" do
        Logger.info("[SSE] hot deal — notificando tambem inscritos em 'destaque'")
        Gateway.SSERegistry.notify("destaque", sse_json)
      end
    else
      false ->
        Logger.warning("[SSE] assinatura invalida em promocao.categoria.#{rest} — descartado")

      {:error, reason} ->
        Logger.warning("[SSE] payload invalido em promocao.categoria.#{rest}: #{inspect(reason)}")

      other ->
        Logger.warning("[SSE] payload sem categoria: #{inspect(other)}")
    end
  end

  defp handle_message(routing_key, _payload) do
    Logger.debug("Mensagem ignorada no Gateway: #{routing_key}")
  end

  # Serializa o conteudo da notificacao no formato flat esperado pelos
  # clientes SSE: {tipo, categoria, promo_id, promo, source, timestamp}.
  # Os campos source/timestamp vem do envelope assinado.
  defp build_sse_payload(%Event{} = event) do
    event.payload
    |> Map.put("source", event.source)
    |> Map.put("timestamp", DateTime.to_iso8601(event.timestamp))
    |> Jason.encode()
  end
end
