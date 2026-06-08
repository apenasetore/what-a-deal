defmodule Gateway.Consumer do
  @moduledoc """
  Consome eventos `promocao.publicada` do RabbitMQ.

  Ao receber um evento, verifica a assinatura digital usando a chave
  publica do MS Promocao. Se valida, armazena a promocao no DealStore
  local. Eventos com assinatura invalida sao descartados com log de warning.
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
      # Registra a promocao validada no DealStore para o frontend buscar via API REST
      Gateway.DealStore.add(promo)
      Logger.info("Promocao validada recebida: #{promo["nome"]}")
    else
      false ->
        Logger.warning("Assinatura invalida em promocao.publicada — evento descartado")

      {:error, reason} ->
        Logger.error("Erro ao processar promocao.publicada: #{inspect(reason)}")
    end
  end


  defp handle_message("promocao.categoria.destaque", payload) do
    with {:ok, event} <- Envelope.decode(payload),
         {:ok, public_key} <- Crypto.load_public_key("ranking"),
         true <- Event.verify(event, public_key) do
      # Normaliza o envelope do Ranking no mesmo formato de notificacao do
      # MS Notificacao, para o frontend tratar todos os eventos igual.
      notificacao = %{
        "tipo" => "hot deal",
        "categoria" => event.payload["categoria"],
        "promo_id" => event.payload["id"] || event.id,
        "source" => event.source,
        "timestamp" => DateTime.to_iso8601(event.timestamp),
        "promo" => event.payload
      }

      Gateway.SSE.broadcast_category("destaque", notificacao)
      Logger.info("SSE destaque enviado: #{event.payload["nome"]}")
    else
      false ->
        Logger.warning("Assinatura invalida em promocao.categoria.destaque — descartado")

      {:error, reason} ->
        Logger.error("Erro ao processar promocao.categoria.destaque: #{inspect(reason)}")
    end
  end

  # Notificacoes por categoria vindas do MS Notificacao: JSON puro (nao
  # assinado), ja no formato %{"tipo" => ..., "categoria" => ...,
  # "promo" => ...}. Repassamos o mapa inteiro pro frontend.
  defp handle_message("promocao.categoria." <> categoria, payload) do
    case Jason.decode(payload) do
      {:ok, notificacao} ->
        Gateway.SSE.broadcast_category(categoria, notificacao)

      {:error, reason} ->
        Logger.warning("Erro ao decodificar promocao.categoria.#{categoria}: #{inspect(reason)}")
    end
  end

  defp handle_message(routing_key, _payload) do
    Logger.debug("Mensagem ignorada no Gateway: #{routing_key}")
  end
end
