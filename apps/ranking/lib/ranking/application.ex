defmodule Ranking.Application do
  @moduledoc false

  use Application

  @rabbitmq_name :ranking_rabbitmq
  @queue "fila_ranking"
  @routing_keys ["promocao.voto"]

  @impl true
  def start(_type, _args) do
    if Application.get_env(:ranking, :autostart, true) do
      rabbitmq_url =
        Application.get_env(:ranking, :rabbitmq_url, "amqp://guest:guest@localhost")

      children = [
        Ranking.VoteStore,
        {Shared.RabbitMQ,
         name: @rabbitmq_name, url: rabbitmq_url, queues: [{@queue, @routing_keys}]}
      ]

      opts = [strategy: :one_for_one, name: Ranking.Supervisor]

      case Supervisor.start_link(children, opts) do
        {:ok, pid} ->
          Ranking.Consumer.start(@rabbitmq_name)
          {:ok, pid}

        error ->
          error
      end
    else
      Supervisor.start_link([], strategy: :one_for_one, name: Ranking.Supervisor)
    end
  end
end
