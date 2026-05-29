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

  # TODO colocar promoção destaque para consumir.
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

  defp handle_message(routing_key, _payload) do
    Logger.debug("Mensagem ignorada no Gateway: #{routing_key}")
  end
end
