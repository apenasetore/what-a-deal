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
          Gateway.SSERegistry,
          {Plug.Cowboy,
           scheme: :http,
           plug: Gateway.Router,
           options: [
             port: 4000,
             protocol_options: [idle_timeout: :infinity],
             dispatch: [
               {:_,
                [
                  {"/notifications/:client_name", Gateway.SSEHandler, []},
                  {:_, Plug.Cowboy.Handler, {Gateway.Router, []}}
                ]}
             ]
           ]},
          {Shared.RabbitMQ,
           name: :gateway_rabbitmq,
           url: rabbitmq_url,
           queues: [
             {"gateway_promocoes", ["promocao.publicada"]},
             {"gateway_sse", ["promocao.categoria.#"]}
           ]},
          Gateway.Consumer
        ]
      else
        []
      end

    opts = [strategy: :rest_for_one, name: Gateway.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
