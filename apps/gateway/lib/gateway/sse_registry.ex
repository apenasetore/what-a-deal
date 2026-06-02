defmodule Gateway.SSERegistry do
  @moduledoc """
  Registro de conexoes SSE ativas por cliente.

  Mapeia client_name -> MapSet de PIDs ouvindo SSE.
  Ao receber notificacao de uma categoria, consulta SubscriptionStore
  para descobrir quais clientes assinaram aquela categoria e envia
  {:sse_event, payload} para cada PID registrado.
  """

  use Agent

  require Logger

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @spec register(String.t(), pid()) :: :ok
  def register(client_name, pid) do
    Agent.update(__MODULE__, fn state ->
      Map.update(state, client_name, MapSet.new([pid]), &MapSet.put(&1, pid))
    end)

    Logger.info("[SSE] cliente=#{client_name} pid=#{inspect(pid)} conectado")
  end

  @spec unregister(String.t(), pid()) :: :ok
  def unregister(client_name, pid) do
    Agent.update(__MODULE__, fn state ->
      Map.update(state, client_name, MapSet.new(), &MapSet.delete(&1, pid))
    end)

    Logger.info("[SSE] cliente=#{client_name} pid=#{inspect(pid)} desconectado")
  end

  @spec notify(String.t(), binary()) :: :ok
  def notify(category, payload) do
    all_state = Agent.get(__MODULE__, & &1)

    Logger.info("[SSE] notify categoria=#{category} clientes_registrados=#{map_size(all_state)}")

    Enum.each(all_state, fn {client_name, pids} ->
      subscriptions = Gateway.SubscriptionStore.list(client_name) || []
      subscribed? = category in subscriptions

      Logger.info(
        "[SSE] cliente=#{client_name} subscriptions=#{inspect(subscriptions)} match=#{subscribed?}"
      )

      if subscribed? do
        Enum.each(pids, fn pid ->
          if Process.alive?(pid) do
            Logger.info("[SSE] pid=#{inspect(pid)} alive?=true, enviando evento")
            send(pid, {:sse_event, payload})
          else
            Logger.info("[SSE] pid=#{inspect(pid)} alive?=false, removendo PID stale")
            unregister(client_name, pid)
          end
        end)
      end
    end)
  end
end
