{:ok, _} = Application.ensure_all_started(:event_bus)
{:ok, _} = Application.ensure_all_started(:sse)

topic = Gateway.SSE.client_topic("Bubba")
IO.puts("topic = #{inspect(topic)}")

# 1) registra o topico (como Gateway.SSE.stream/2 faz via ensure_topic)
unless EventBus.topic_exist?(topic), do: EventBus.register_topic(topic)

# 2) inscreve este processo EXATAMENTE como a lib :sse faz (SSE.Server.subscribe_sse)
listener = {SSE, %{pid: self(), matcher: {}}}
EventBus.subscribe({listener, ["^#{topic}$"]})

IO.puts("subscribers(#{inspect(topic)}) = #{inspect(EventBus.Manager.Subscription.subscribers(topic))}")

# 3) faz o broadcast (como Gateway.SSE.broadcast_category/2)
chunk = %SSE.Chunk{data: Jason.encode!(%{tipo: "hot deal", promo: %{nome: "PC"}})}
EventBus.notify(%EventBus.Model.Event{id: 1, topic: topic, data: chunk, source: "test"})

receive do
  {:sse, ^topic, id} ->
    data = EventBus.fetch_event_data({topic, id})
    IO.puts("✅ RECEBIDO via SSE shadow: #{inspect(data.data)}")
after
  1500 -> IO.puts("❌ TIMEOUT — EventBus NAO entregou (bug no backend)")
end
