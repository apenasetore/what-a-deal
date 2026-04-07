defmodule Gateway.PromoStore do
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
  def add(%{"id" => id} = promo) do
    Agent.update(__MODULE__, &Map.put(&1, id, promo))
  end

  @spec list() :: [map()]
  def list do
    Agent.get(__MODULE__, &Map.values(&1))
  end

  @spec get(String.t()) :: map() | nil
  def get(id) do
    Agent.get(__MODULE__, &Map.get(&1, id))
  end

  @spec count() :: non_neg_integer()
  def count do
    Agent.get(__MODULE__, &map_size(&1))
  end

  @spec clear() :: :ok
  def clear do
    Agent.update(__MODULE__, fn _ -> %{} end)
  end
end
