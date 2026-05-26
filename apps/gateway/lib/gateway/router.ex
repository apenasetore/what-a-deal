# lib/gateway/router.ex
defmodule Gateway.Router do
  use Plug.Router

  plug :match
  plug :dispatch

  get "/hello" do
    send_resp(conn, 200, "Hello, world!")
  end

  get "/deals" do
    deals = Gateway.PromoStore.list()
    send_resp(conn, 200, Jason.encode!(deals))
  end

  post "/deals" do
    Gateway.RestAPI.call_post_deal(conn, [])
  end

  # get "/clients" do
  #     clients = Gateway.PromoStore.get_clients()
  #     send_resp(conn, 200, Jason.encode!(clients))
  #   end

  # post "/clients" do
  #   Gateway.RestAPI.call_post_client(conn, [])
  # end
end


# GET
# listar_promocoes
# cliente
# get /deals/, DelsContoller: show
# POST
# criar_cliente
# cliente
# post "/clients", ClientController, :create
# POST
# registar_interesse
# cliente
# post “/subscription/”, SubscriptionController :create
# DELETE
# cancelar_interesse
# cliente
# delete“/subscription/”, SubscriptionController :delete
# PATCH
# votar_promocao
# cliente
# patch /deals/, DelsContoller: update
# POST
# criar_loja
# loja
# post “/store/”, StoreController :create
# POST
# criar_promocao
# loja
# post “/deal/”, DealController :create
# DELETE
# deletar_promocao
# loja
# delete “/deal/”, StoreController :delete
