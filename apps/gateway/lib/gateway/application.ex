defmodule Gateway.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    rabbitmq_url = Application.get_env(:gateway, :rabbitmq_url, "amqp://guest:guest@localhost")

    children = [
      Gateway.PromoStore,
      {Shared.RabbitMQ,
       name: :gateway_rabbitmq,
       url: rabbitmq_url,
       queues: [{"gateway_promocoes", ["promocao.publicada"]}]},
      Gateway.Consumer
    ]

    opts = [strategy: :rest_for_one, name: Gateway.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
