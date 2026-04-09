defmodule Notificacao.Application do
  @moduledoc """
  Application callback do MS Notificacao.

  Inicia a supervision tree do servico:

  1. `Shared.RabbitMQ` — wrapper de conexao AMQP, configurado para
     declarar a fila `fila_notificacao` bindada nas routing keys
     `promocao.publicada` e `promocao.destaque`
  2. `Notificacao.Consumer` — registra callback que valida assinatura
     dos eventos recebidos e republica em `promocao.<categoria>`

  ## Configuracao

  A URL do RabbitMQ pode ser sobrescrita via variavel de ambiente
  `RABBITMQ_URL`. Default: `amqp://guest:guest@localhost`.

  ## Pre-requisitos

  As chaves publicas dos servicos `promocao` e `ranking` devem existir
  em `apps/shared/priv/keys/<servico>/public.pem` antes do startup. Use
  `mix gen_keys` para gera-las.

  Notificacao nao possui chaves proprias — apenas valida assinaturas e
  republica os envelopes originais (preservando a assinatura) em routing
  keys de categoria.
  """

  use Application

  @rabbitmq_name :notificacao_rabbitmq
  @queue "fila_notificacao"
  @routing_keys ["promocao.publicada", "promocao.categoria.destaque"]

  @impl true
  def start(_type, _args) do
    if Application.get_env(:notificacao, :autostart, true) do
      children = [
        {Shared.RabbitMQ,
         name: @rabbitmq_name, url: rabbitmq_url(), queues: [{@queue, @routing_keys}]}
      ]

      opts = [strategy: :one_for_one, name: Notificacao.Supervisor]

      case Supervisor.start_link(children, opts) do
        {:ok, pid} ->
          Notificacao.Consumer.start(@rabbitmq_name)
          {:ok, pid}

        error ->
          error
      end
    else
      Supervisor.start_link([], strategy: :one_for_one, name: Notificacao.Supervisor)
    end
  end

  @doc false
  def rabbitmq_name, do: @rabbitmq_name

  @doc false
  def queue, do: @queue

  @doc false
  def routing_keys, do: @routing_keys

  @doc false
  def rabbitmq_url do
    System.get_env("RABBITMQ_URL", "amqp://guest:guest@localhost")
  end
end
