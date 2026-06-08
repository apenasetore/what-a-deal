import Config

# Credenciais do Gmail injetadas em runtime (nao versionadas).
# Gere um App Password (16 chars) na conta Google com verificacao em 2 etapas
# ativa — o Gmail rejeita a senha de login normal via SMTP.
config :notificacao, Notificacao.Mailer,
  username: System.get_env("GMAIL_USER"),
  password: System.get_env("GMAIL_APP_PASSWORD")
