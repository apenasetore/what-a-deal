defmodule Gateway.Application do
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    ensure_keys!()

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

  defp ensure_keys! do
    case Shared.Crypto.load_private_key("gateway") do
      {:ok, _} ->
        :ok

      {:error, _} ->
        Logger.info("Gerando par de chaves RSA para o Gateway...")
        {priv, pub} = Shared.Crypto.generate_key_pair()
        Shared.Crypto.save_keys("gateway", priv, pub)
    end
  end
end
