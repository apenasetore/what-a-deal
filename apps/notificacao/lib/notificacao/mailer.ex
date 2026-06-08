defmodule Notificacao.Mailer do
  @moduledoc """
  Mailer do MS Notificacao (Swoosh).

  Usa o adapter SMTP configurado em `config/config.exs` (servidor do Gmail).
  As credenciais (`username`/`password`) vem das variaveis de ambiente
  `GMAIL_USER` e `GMAIL_APP_PASSWORD`, injetadas em `config/runtime.exs`.
  """
  use Swoosh.Mailer, otp_app: :notificacao
end
