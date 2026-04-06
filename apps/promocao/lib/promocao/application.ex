defmodule Promocao.Application do
  @moduledoc """
  Application callback do MS Promocao.

  Inicia a supervision tree do servico:

  1. `Shared.RabbitMQ` — wrapper de conexao AMQP, configurado para
     declarar a fila `fila_promocao` bindada a routing key `promocao.recebida`
  2. `Promocao.Consumer` — registra callback que processa eventos recebidos,
     valida assinatura e republica como `promocao.publicada`

  ## Configuracao

  A URL do RabbitMQ pode ser sobrescrita via variavel de ambiente
  `RABBITMQ_URL`. Default: `amqp://guest:guest@localhost`.

  ## Pre-requisitos

  As chaves do servico devem existir em `apps/shared/priv/keys/promocao/`
  antes do startup. Use `Shared.Crypto.generate_key_pair/0` e
  `Shared.Crypto.save_keys/3` para gera-las.
  """

  use Application

  @rabbitmq_name :promocao_rabbitmq
  @queue "fila_promocao"
  @routing_keys ["promocao.recebida"]

  @impl true
  def start(_type, _args) do
    children = [
      {Shared.RabbitMQ,
       name: @rabbitmq_name,
       url: rabbitmq_url(),
       queues: [{@queue, @routing_keys}]}
    ]

    opts = [strategy: :one_for_one, name: Promocao.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Promocao.Consumer.start(@rabbitmq_name)
        {:ok, pid}

      error ->
        error
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
