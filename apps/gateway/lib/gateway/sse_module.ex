defmodule Gateway.SSE do
  @moduledoc """
  Server-Sent Events (SSE) do Gateway.

  Mantem conexoes HTTP abertas com os clientes e empurra promocoes em
  tempo real.

  ## Roteamento por cliente (e nao por categoria)

  Cada conexao se inscreve num unico topico do `EventBus`: o **topico
  pessoal** do cliente (`:sse_<nome>`). A decisao de quem recebe cada
  notificacao acontece no momento do envio (`broadcast_category/2`), que
  consulta o `Gateway.SubscriptionStore` para descobrir quem segue a
  categoria e notifica apenas esses topicos pessoais.

  Esse desenho resolve dois problemas:

    1. O `EventBus` casa topico x assinante via regex; uma lista de
       padroes **vazia** compila para `~r//`, que casa com tudo — ou seja,
       inscrever uma conexao em zero categorias faria ela receber TODAS as
       notificacoes. Como o topico pessoal nunca e vazio, isso nao ocorre.

    2. Como a inscricao e consultada no envio, novas categorias seguidas
       (POST /subscription) passam a valer **sem o cliente reconectar**.

  Fluxo completo:

      MS Notificacao / MS Ranking
        --(RabbitMQ: promocao.categoria.#)--> Gateway.Consumer
          --> Gateway.SSE.broadcast_category/2
                (SubscriptionStore.clients_for/1 + EventBus.notify por cliente)
            --> conexoes SSE dos clientes que seguem a categoria
              --> cliente (text/event-stream)
  """

  alias SSE.Chunk
  alias EventBus.Model.Event, as: BusEvent

  require Logger

  @doc """
  Mantem a requisicao aberta como um stream SSE para `client_name`.

  Inscreve a conexao no topico pessoal do cliente e envia um evento
  inicial `ready`. Bloqueia o processo da requisicao ate o cliente
  desconectar.
  """
  @spec stream(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def stream(conn, client_name) do
    topic = client_topic(client_name)
    ensure_topic(topic)

    Logger.info("SSE: cliente #{client_name} conectado (topico #{inspect(topic)})")

    welcome = %Chunk{
      event: "ready",
      data: Jason.encode!(%{client_name: client_name})
    }

    # O frontend conecta direto no gateway (sem o proxy do Vite), entao a
    # resposta precisa liberar CORS para a origem do EventSource.
    conn
    |> Plug.Conn.put_resp_header("access-control-allow-origin", "*")
    |> SSE.stream({[topic], welcome})
  end

  @doc """
  Entrega `notification` a todos os clientes inscritos em `category`.

  O roteamento e feito no envio: consulta o `SubscriptionStore` e notifica
  o topico pessoal de cada cliente que segue a categoria. `notification` e
  o mapa no formato do MS Notificacao (`%{"tipo" => ..., "categoria" => ...,
  "promo" => ...}`), serializado como JSON no campo `data` do SSE.

  O evento SSE vai **sem nome** (`event:` em branco) de proposito: o
  frontend escuta tudo via `EventSource.onmessage` e diferencia
  `nova`/`hot deal` pelo campo `tipo` do payload.
  """
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

  @doc """
  Topico pessoal de um cliente (cada aba conecta neste topico).

      iex> Gateway.SSE.client_topic("alice")
      :sse_alice
  """
  @spec client_topic(String.t()) :: atom()
  def client_topic(client_name) when is_binary(client_name) do
    String.to_atom("sse_" <> client_name)
  end

  # --- internos ---

  # Topicos do EventBus precisam ser registrados antes do notify. Idempotente.
  defp ensure_topic(topic) do
    unless EventBus.topic_exist?(topic), do: EventBus.register_topic(topic)
    :ok
  end

  defp unique_id, do: System.unique_integer([:positive, :monotonic])
end
