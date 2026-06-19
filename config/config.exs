import Config

config :gateway, rabbitmq_url: "amqp://guest:guest@localhost"

config :swoosh, :api_client, false

config :notificacao, Notificacao.Mailer,
  adapter: Swoosh.Adapters.SMTP,
  relay: "smtp.gmail.com",
  port: 587,
  tls: :always,
  auth: :always,
  ssl: false,
  retries: 1,

  tls_options: [
    verify: :verify_none,
    versions: [:"tlsv1.2", :"tlsv1.3"],
    server_name_indication: ~c"smtp.gmail.com"
  ]

config :logger, :console,
  level: :info,
  format: "$date $time [$level] $metadata$message\n",
  metadata: [:service]

import_config "#{config_env()}.exs"
