defmodule Gateway.SSE do

  alias SSE.Chunk
  alias EventBus.Model.Event, as: BusEvent

  require Logger

  @spec stream(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def stream(conn, client_name) do
    topic = client_topic(client_name)
    ensure_topic(topic)

    Logger.info("SSE: cliente #{client_name} conectado (topico #{inspect(topic)})")

    welcome = %Chunk{
      event: "ready",
      data: Jason.encode!(%{client_name: client_name})
    }

    conn
    |> Plug.Conn.put_resp_header("access-control-allow-origin", "*")
    |> SSE.stream({[topic], welcome})
  end


  @spec broadcast_category(String.t(), map()) :: :ok
  def broadcast_category(category, notification) do
    chunk = %Chunk{data: Jason.encode!(notification)}

    category
    |> Gateway.SubscriptionStore.clients_for()
    |> Enum.each(fn client ->
      topic = client_topic(client)
      ensure_topic(topic)

      EventBus.notify(%BusEvent{
        id: unique_id(),
        topic: topic,
        data: chunk,
        source: "gateway_sse"
      })
    end)
  end


  @spec client_topic(String.t()) :: atom()
  def client_topic(client_name) when is_binary(client_name) do
    String.to_atom("sse_" <> client_name)
  end

  defp ensure_topic(topic) do
    unless EventBus.topic_exist?(topic), do: EventBus.register_topic(topic)
    :ok
  end

  defp unique_id, do: System.unique_integer([:positive, :monotonic])
end
