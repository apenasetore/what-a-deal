defmodule Gateway do
  @moduledoc """
  Microsservico Gateway — interface terminal para cadastro e votacao de promocoes.

  Publica eventos `promocao.recebida` e `promocao.voto` no RabbitMQ,
  e consome `promocao.publicada` para manter uma lista local de
  promocoes validadas pelo MS Promocao.

  ## Uso

      iex -S mix
      iex> Gateway.start()
  """

  def start do
    Gateway.CLI.loop()
  end
end
