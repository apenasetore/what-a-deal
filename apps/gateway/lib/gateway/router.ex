# lib/gateway/router.ex
defmodule Gateway.Router do
  use Plug.Router

  plug(:match)
  plug(:dispatch)

  get "/health" do
    send_resp(conn, 200, "Health check passed!")
  end

  get "/deals" do
    deals = Gateway.DealStore.list()
    send_resp(conn, 200, Jason.encode!(deals))
  end

  post "/deals" do
    Gateway.DealRestAPI.call_post_deal_publish(conn, [])
  end

  post "/store" do
    Gateway.StoreRestAPI.call_post_store(conn, [])
  end

  post "/subscription" do
    Gateway.SubscriptionRestAPI.call_post_subscription(conn, [])
  end

  get "/subscription/:cliente_name" do
    client_name = conn.params["cliente_name"]
    categories = Gateway.SubscriptionStore.list(client_name)
    send_resp(conn, 200, Jason.encode!(%{client_name: client_name, categories: categories}))
  end

  delete "/subscription" do
    Gateway.SubscriptionRestAPI.call_delete_subscription(conn, [])
  end

  post "/vote" do
    Gateway.DealRestAPI.call_client_vote(conn, [])
  end

  get "/stream/:client_name" do
    Gateway.SSE.stream(conn, conn.params["client_name"])
  end
end
