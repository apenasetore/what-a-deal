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
           } = payload} ->
            promo_data = %{
              "nome" => nome,
              "descricao" => descricao,
              "preco_original" => preco_original,
              "preco_promocional" => preco_promocional,
              "categoria" => categoria,
              "loja" => loja,
              "email" => email
            }

            if valid_store_signature?(promo_data, payload["signature"]) do
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
            else
              conn
              |> put_resp_content_type("application/json")
              |> send_resp(401, Jason.encode!(%{error: "Invalid or missing signature"}))
            end

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

  # Verifica a assinatura da loja sobre a promocao usando a chave publica
  # cadastrada no login da loja. Reconstroi a mesma mensagem que o

  # front-end assinou (mesma ordem de campos, precos com 2 casas decimais).
  defp valid_store_signature?(_promo, nil), do: false

  defp valid_store_signature?(promo, signature_b64) do
    with {:ok, signature} <- Base.decode64(signature_b64),
         pub_pem when is_binary(pub_pem) <- Gateway.StoreStore.get_key(promo["loja"]) do
      Shared.Crypto.verify_pem(canonical_deal(promo), signature, pub_pem)
    else
      _ -> false
    end
  end

  defp canonical_deal(promo) do
    Enum.join(
      [
        promo["loja"],
        promo["nome"],
        promo["descricao"],
        promo["categoria"],
        promo["email"],
        format_price(promo["preco_original"]),
        format_price(promo["preco_promocional"])
      ],
      "|"
    )
  end

  # Formata o preco com 2 casas decimais, espelhando Number.toFixed(2) do JS.
  defp format_price(price) when is_integer(price), do: format_price(price * 1.0)
  defp format_price(price) when is_float(price), do: :erlang.float_to_binary(price, decimals: 2)

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
