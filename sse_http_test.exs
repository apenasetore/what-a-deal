{:ok, _} = Application.ensure_all_started(:event_bus)
{:ok, _} = Application.ensure_all_started(:sse)
{:ok, _} = Application.ensure_all_started(:plug_cowboy)
{:ok, _} = Gateway.SubscriptionStore.start_link([])

Gateway.SubscriptionStore.add(%{"client_name" => "Bubba", "category" => "destaque"})

{:ok, _} = Plug.Cowboy.http(Gateway.Router, [], port: 4099)
IO.puts(:stderr, "SERVER_UP on 4099")

# broadcast a cada 2s por 30s, logando quantos assinantes existem
spawn(fn ->
  for n <- 1..15 do
    Process.sleep(2000)
    subs = EventBus.Manager.Subscription.subscribers(:sse_Bubba)
    IO.puts(:stderr, "tick #{n}: subscribers(:sse_Bubba)=#{length(subs)}")
    Gateway.SSE.broadcast_category("destaque", %{"tipo" => "hot deal", "n" => n, "promo" => %{"nome" => "PC#{n}"}})
  end
end)

Process.sleep(32000)
