defmodule Gateway.StoreRestAPI do
  import Plug.Conn

  def init(options), do: options

  def call_post_store(conn, _opts) do
    case get_req_header(conn, "content-type") do
      ["application/json"] ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)

        case Jason.decode(body) do
          {:ok, %{"nome" => nome, "pubKey" => pubKey}} ->
            Gateway.StoreStore.add(%{"nome" => nome, "pubKey" => pubKey})
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(200, Jason.encode!(%{message: "Store added successfully"}))

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
