defmodule Gateway.SSEHandler do
  @moduledoc """
  Cowboy loop handler para SSE.

  Usa o behaviour :cowboy_loop (projetado para long-polling/streaming),
  que processa mensagens via info/3 e garante terminate/3 ao fechar conexao.
  Evita os problemas de bloquear init/2 no cowboy_handler usado pelo Plug.
  """

  @behaviour :cowboy_loop

  require Logger

  @keepalive_ms 15_000

  @impl :cowboy_loop
  def init(req, _opts) do
    client_name = :cowboy_req.binding(:client_name, req)

    headers = %{
      "content-type" => "text/event-stream",
      "cache-control" => "no-cache",
      "connection" => "keep-alive",
      "access-control-allow-origin" => "*",
      "x-accel-buffering" => "no"
    }

    req = :cowboy_req.stream_reply(200, headers, req)
    :cowboy_req.stream_body(": connected\n\n", :nofin, req)

    Logger.info("[SSE] conexao iniciada cliente=#{client_name} pid=#{inspect(self())}")
    Gateway.SSERegistry.register(client_name, self())

    Process.send_after(self(), :keepalive, @keepalive_ms)

    {:cowboy_loop, req, %{client_name: client_name}}
  end

  @impl :cowboy_loop
  def info({:sse_event, data}, req, state) do
    Logger.info("[SSE] enviando evento para cliente=#{state.client_name}")
    :cowboy_req.stream_body("data: #{data}\n\n", :nofin, req)
    {:ok, req, state}
  end

  def info(:keepalive, req, state) do
    Logger.info("[SSE] keepalive cliente=#{state.client_name}")
    :cowboy_req.stream_body(": keepalive\n\n", :nofin, req)
    Process.send_after(self(), :keepalive, @keepalive_ms)
    {:ok, req, state}
  end

  def info({:tcp_closed, _socket}, req, state) do
    Logger.info("[SSE] tcp_closed cliente=#{state.client_name}")
    {:stop, req, state}
  end

  def info({:tcp_error, _socket, reason}, req, state) do
    Logger.info("[SSE] tcp_error cliente=#{state.client_name}: #{inspect(reason)}")
    {:stop, req, state}
  end

  def info(msg, req, state) do
    Logger.debug("[SSE] mensagem inesperada #{state.client_name}: #{inspect(msg)}")
    {:ok, req, state}
  end

  @impl :cowboy_loop
  def terminate(reason, _req, state) do
    Logger.info("[SSE] conexao encerrada cliente=#{state.client_name} razao=#{inspect(reason)}")
    Gateway.SSERegistry.unregister(state.client_name, self())
    :ok
  end
end
