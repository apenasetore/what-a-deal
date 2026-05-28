defmodule Gateway.DealStore do
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
  def add(%{"id" => id} = deal) do
    Agent.update(__MODULE__, &Map.put(&1, id, deal))
  end

  @spec list() :: [map()]
  def list do
    Agent.get(__MODULE__, &Map.values(&1))
  end
end
