defmodule Gateway.StoreStore do
  @moduledoc """
  Agent que mantem cache local das promocoes validadas pelo MS Promocao.

  Quando o Gateway consome eventos `promocao.publicada`, armazena os dados
  aqui para que a CLI possa listar promocoes e permitir votacao sem
  depender de chamada sincrona ao MS Promocao.
  """

  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @spec add(map()) :: :ok
  def add(%{"nome" => nome, "pubKey" => pubKey} = store) do
    Agent.update(__MODULE__, &Map.put(&1, nome, pubKey))
  end

  @spec get_key() :: [map()]
  def get_key(nome)do
    Agent.get(__MODULE__, &Map.get(&1, nome))
  end
end
