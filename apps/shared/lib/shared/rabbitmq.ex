defmodule Shared.RabbitMQ do
  @moduledoc """
  GenServer que gerencia conexao AMQP com o RabbitMQ.

  Encapsula conexao, channel, declaracao de exchange/filas e pub/sub
  num unico processo. Cada microsservico inicia sua propria instancia
  na supervision tree.

  ## Responsabilidades

  - Conectar ao RabbitMQ e abrir channel
  - Declarar o exchange topic `"promocoes"` (durable)
  - Declarar filas e fazer bind com routing keys
  - Publicar mensagens no exchange
  - Consumir mensagens e encaminhar para um callback
  - Reconectar automaticamente com backoff exponencial em caso de queda

  ## Exemplo de uso

      # Na supervision tree (application.ex):
      children = [
        {Shared.RabbitMQ,
          name: :gateway_rabbitmq,
          url: "amqp://guest:guest@localhost",
          queues: [{"fila_gateway", ["promocao.publicada"]}]}
      ]

      # Publicar:
      Shared.RabbitMQ.publish(:gateway_rabbitmq, "promocao.recebida", json)

      # Registrar callback para consumir:
      Shared.RabbitMQ.subscribe(:gateway_rabbitmq, fn routing_key, payload ->
        IO.puts("Recebido \#{routing_key}")
      end)

  ## Reconnect

  Quando a conexao cai, o GenServer agenda uma tentativa de reconexao
  com backoff exponencial: 1s, 2s, 4s, 8s, ..., ate o maximo de 30s.
  Ao reconectar, redeclara filas, bindings e retoma o consumo.
  """

  use GenServer

  require Logger

  @exchange "promocoes"
  @exchange_type :topic
  @initial_backoff 1_000
  @max_backoff 30_000

  # --- API publica ---

  @doc """
  Inicia o GenServer de conexao AMQP.

  ## Opcoes

  - `:name` — nome para registro local (ex: `:gateway_rabbitmq`)
  - `:url` — URL de conexao AMQP (ex: `"amqp://guest:guest@localhost"`)
  - `:queues` — lista de `{nome_fila, [routing_keys]}` para declarar e bindar
  - `:queue_opts` — opcoes para `AMQP.Queue.declare/3` (default: `[]`). Ex: `[auto_delete: true]` para testes

  ## Exemplo

      Shared.RabbitMQ.start_link(
        name: :gateway_rabbitmq,
        url: "amqp://guest:guest@localhost",
        queues: [{"fila_gateway", ["promocao.publicada"]}]
      )
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Publica uma mensagem no exchange `"promocoes"` com a routing key dada.

  Retorna `:ok` ou `{:error, reason}` se nao houver conexao ativa.

  ## Exemplo

      :ok = Shared.RabbitMQ.publish(:gateway_rabbitmq, "promocao.recebida", json)
  """
  @spec publish(GenServer.server(), String.t(), binary()) :: :ok | {:error, term()}
  def publish(server, routing_key, payload) do
    GenServer.call(server, {:publish, routing_key, payload})
  end

  @doc """
  Registra um callback para processar mensagens consumidas das filas.

  O callback recebe `(routing_key, payload)` e sera chamado para cada
  mensagem entregue pelo RabbitMQ.

  ## Exemplo

      Shared.RabbitMQ.subscribe(:gateway_rabbitmq, fn routing_key, payload ->
        IO.puts("Recebido: \#{routing_key}")
      end)
  """
  @spec subscribe(GenServer.server(), (String.t(), String.t() -> any())) :: :ok
  def subscribe(server, callback) do
    GenServer.call(server, {:subscribe, callback})
  end

  # --- Callbacks do GenServer ---

  @doc false
  @impl true
  def init(opts) do
    queue_opts = Keyword.get(opts, :queue_opts, [])

    with {:ok, url} <- Keyword.fetch(opts, :url),
         {:ok, queues} <- Keyword.fetch(opts, :queues),
         {:ok, connection, channel} <- connect(url, queues, queue_opts) do
      {:ok,
       %{
         connection: connection,
         channel: channel,
         callback: nil,
         config: opts,
         backoff: @initial_backoff
       }}
    else
      {:error, reason} ->
        Logger.warning("Falha ao conectar ao RabbitMQ: #{inspect(reason)}. Reagendando...")
        Process.send_after(self(), :reconnect, @initial_backoff)

        {:ok,
         %{connection: nil, channel: nil, callback: nil, config: opts, backoff: @initial_backoff}}
    end
  end

  @doc false
  @impl true
  def handle_call({:publish, _routing_key, _payload}, _from, %{channel: nil} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  @doc false
  @impl true
  def handle_call({:publish, routing_key, payload}, _from, state) do
    AMQP.Basic.publish(state.channel, @exchange, routing_key, payload)
    {:reply, :ok, state}
  end

  @doc false
  @impl true
  def handle_call({:subscribe, callback}, _from, state) do
    Enum.each(state.config[:queues], fn {queue_name, _topics} ->
      AMQP.Basic.consume(state.channel, queue_name)
    end)

    {:reply, :ok, %{state | callback: callback}}
  end

  @doc false
  @impl true
  def handle_info(:reconnect, state) do
    backoff = min(@max_backoff, state.backoff)
    opts = state.config
    url = Keyword.fetch!(opts, :url)
    queues = Keyword.fetch!(opts, :queues)
    queue_opts = Keyword.get(opts, :queue_opts, [])

    case connect(url, queues, queue_opts) do
      {:ok, connection, channel} ->
        if state.callback != nil, do: resubscribe(channel, queues)
        {:noreply, %{state | connection: connection, channel: channel, backoff: @initial_backoff}}

      {:error, reason} ->
        Logger.warning("Falha ao conectar ao RabbitMQ: #{inspect(reason)}. Reagendando...")
        new_backoff = min(backoff * 2, @max_backoff)
        Process.send_after(self(), :reconnect, new_backoff)
        {:noreply, %{state | backoff: new_backoff}}
    end
  end

  defp resubscribe(channel, queues) do
    Logger.info("RabbitMQ reconectado, restaurando subscriptions")
    Enum.each(queues, fn {queue_name, _topics} -> AMQP.Basic.consume(channel, queue_name) end)
  end

  @doc false
  @impl true
  def handle_info({:basic_deliver, payload, meta}, state) do
    channel = state.channel
    tag = meta.delivery_tag

    if state.callback != nil do
      Task.start(fn ->
        state.callback.(meta.routing_key, payload)
        AMQP.Basic.ack(channel, tag)
      end)
    else
      AMQP.Basic.ack(channel, tag)
    end

    {:noreply, state}
  end

  @doc false
  @impl true
  def handle_info({:basic_consume_ok, _meta}, state) do
    {:noreply, state}
  end

  # --- Funcoes privadas ---

  defp connect(url, queues, queue_opts) do
    with {:ok, connection} <- AMQP.Connection.open(url),
         {:ok, channel} <- AMQP.Channel.open(connection) do
      AMQP.Exchange.declare(channel, @exchange, @exchange_type)
      Enum.each(queues, &declare_and_bind_queue(channel, &1, queue_opts))
      {:ok, connection, channel}
    end
  end

  defp declare_and_bind_queue(channel, {queue_name, topics}, queue_opts) do
    AMQP.Queue.declare(channel, queue_name, queue_opts)

    Enum.each(topics, fn topic ->
      AMQP.Queue.bind(channel, queue_name, @exchange, routing_key: topic)
    end)
  end

  @doc false
  def exchange, do: @exchange
  @doc false
  def exchange_type, do: @exchange_type
  @doc false
  def initial_backoff, do: @initial_backoff
  @doc false
  def max_backoff, do: @max_backoff
end
