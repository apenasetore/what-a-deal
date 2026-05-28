# lib/gateway/router.ex
defmodule Gateway.Router do
  use Plug.Router

  plug :match
  plug :dispatch

  # -- Health check -- #
  get "/health" do
    send_resp(conn, 200, "Health check passed!")
  end

    # -- Deals Routes -- #
  get "/deals" do
    deals = Gateway.PromoStore.list()
    send_resp(conn, 200, Jason.encode!(deals))
  end

  post "/deals" do
    Gateway.DealRestAPI.call_post_deal_publish(conn, [])
  end

  post "/subscription" do
    Gateway.SubscriptionRestAPI.call_post_subscription(conn, [])
  end

  get "/subscription/:client" do
    client_id = conn.params["client"]
    client = Gateway.SubscriptionStore.get(client_id)
    send_resp(conn, 200, Jason.encode!(client))
  end

  put "/subscription" do
    Gateway.SubscriptionRestAPI.call_put_subscription(conn, [])
  end


  # -- Registrar voto
  post "/vote" do
    Gateway.RestAPI.call_client_vote(conn, [])
  end

  # --


end
