defmodule Gateway.DealRestAPI do
  import Plug.Conn

  def init(options), do: options

  def call_post_deal_publish(conn, _opts) do
    case get_req_header(conn, "content-type") do
      ["application/json"] ->
        # Read and parse the JSON payload
        {:ok, body, _conn} = Plug.Conn.read_body(conn)

        case Jason.decode(body) do
          {:ok,
           %{
             "nome" => nome,
             "descricao" => descricao,
             "preco_original" => preco_original,
             "preco_promocional" => preco_promocional,
             "categoria" => categoria,
             "loja" => loja,
             "email" => email
           }} ->
            promo_data = %{
              "nome" => nome,
              "descricao" => descricao,
              "preco_original" => preco_original,
              "preco_promocional" => preco_promocional,
              "categoria" => categoria,
              "loja" => loja,
              "email" => email
            }

            status =
              case Gateway.Publisher.publish_promocao(promo_data) do
                :ok -> "Promocao enviada para validacao!"
                {:error, reason} -> "Erro ao enviar: #{inspect(reason)}"
              end

            response = %{
              message: "User data received",
              data: %{
                promo_data: promo_data,
                status: status
              }
            }

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(200, Jason.encode!(response))

          {:error, _reason} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(400, Jason.encode!(%{error: "Invalid JSON format"}))
        end

      _ ->
        # Handle missing or incorrect content-type
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(415, Jason.encode!(%{error: "Unsupported Media Type"}))
    end
  end

  def call_client_vote(conn, _opts) do
    case get_req_header(conn, "content-type") do
      ["application/json"] ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)

        case Jason.decode(body) do
          {:ok,
           %{
             "promo" => %{
               "id" => id,
               "nome" => nome,
               "descricao" => descricao,
               "preco_original" => preco_original,
               "preco_promocional" => preco_promocional,
               "categoria" => categoria,
               "loja" => loja,
               "email" => email
             },
             "vote" => vote
           }} ->
            case vote do
              "up" ->
                Gateway.Publisher.publish_voto(
                  %{
                  "id" => id,
                    "nome" => nome,
                    "descricao" => descricao,
                    "preco_original" => preco_original,
                    "preco_promocional" => preco_promocional,
                    "categoria" => categoria,
                    "loja" => loja,
                    "email" => email
                  },
                  1
                )

              "down" ->
                Gateway.Publisher.publish_voto(
                  %{
                    "id" => id,
                    "nome" => nome,
                    "descricao" => descricao,
                    "preco_original" => preco_original,
                    "preco_promocional" => preco_promocional,
                    "categoria" => categoria,
                    "loja" => loja,
                    "email" => email
                  },
                  -1
                )
              _ ->
                conn
                |> put_resp_content_type("application/json")
                |> send_resp(400, Jason.encode!(%{error: "Invalid vote value"}))
            end

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(200, Jason.encode!(%{message: "Vote registered successfully"}))

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
