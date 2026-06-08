defmodule Gateway.SubscriptionRestAPI do
  import Plug.Conn

  def init(options), do: options

  def call_post_subscription(conn, _opts) do
    case get_req_header(conn, "content-type") do
      ["application/json"] ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)

        case Jason.decode(body) do
          {:ok, %{"client_name" => client_name, "category" => category}} ->
            Gateway.SubscriptionStore.add(%{"client_name" => client_name, "category" => category})
            Gateway.SSE
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(200, Jason.encode!(%{message: "Subscription successful"}))

          {:error, _reason} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(400, Jason.encode!(%{error: "Invalid JSON format"}))
        end

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "Content-Type must be application/json"}))
    end
  end

  def call_delete_subscription(conn, _opts) do
    case get_req_header(conn, "content-type") do
      ["application/json"] ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)

        case Jason.decode(body) do
          {:ok, %{"client_name" => client_name, "category" => category}} ->
            Gateway.SubscriptionStore.delete(%{
              "client_name" => client_name,
              "category" => category
            })

            categories = Gateway.SubscriptionStore.list(client_name)

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(200, Jason.encode!(%{client_name: client_name, categories: categories}))

          {:error, _reason} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(400, Jason.encode!(%{error: "Invalid JSON format"}))
        end

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "Content-Type must be application/json"}))
    end
  end
end
