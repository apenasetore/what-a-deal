# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
import Config

config :gateway, rabbitmq_url: "amqp://guest:guest@localhost"

# Swoosh: nao usamos adapters baseados em HTTP API, entao desligamos o client
# (evita warning no boot).
config :swoosh, :api_client, false

# Mailer do MS Notificacao via SMTP do Gmail. username/password vem do
# config/runtime.exs (env vars GMAIL_USER / GMAIL_APP_PASSWORD).
config :notificacao, Notificacao.Mailer,
  adapter: Swoosh.Adapters.SMTP,
  relay: "smtp.gmail.com",
  port: 587,
  tls: :always,
  auth: :always,
  ssl: false,
  retries: 1,
  # OTP recente usa verify_peer por padrao, mas o gen_smtp nao traz o bundle de
  # CAs — sem isso o handshake TLS com o Gmail falha (:tls_failed). Desligamos a
  # verificacao do certificado e fixamos SNI/versoes.
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
