defmodule Gateway.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:gateway, :autostart, true) do
        rabbitmq_url =
          Application.get_env(:gateway, :rabbitmq_url, "amqp://guest:guest@localhost")

        [
          Gateway.DealStore,
          Gateway.SubscriptionStore,
          {Plug.Cowboy, scheme: :http, plug: Gateway.Router, options: [port: 4000]},
          {Shared.RabbitMQ,
           name: :gateway_rabbitmq,
           url: rabbitmq_url,
           queues: [{"gateway_promocoes", ["promocao.publicada"]}]},
          Gateway.Consumer
        ]
      else
        []
      end

    opts = [strategy: :rest_for_one, name: Gateway.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
