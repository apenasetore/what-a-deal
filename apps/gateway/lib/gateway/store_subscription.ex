defmodule Gateway.SubscriptionStore do
  @moduledoc """
  Agent que mantem cache local das inscricoes.
  """

  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  # Ele adicionna uma categoria de interesse para um cliente, se cliente não existe cria ciente+categoria de interesse.
  @spec add(map()) :: :ok
  def add(%{"client_name" => client_name, "category" => category} = _subscription) do
    categories =
      case Agent.get(__MODULE__, &Map.get(&1, client_name)) do
        nil -> [category]
        existing -> Enum.uniq([category | existing])
      end

    Agent.update(__MODULE__, &Map.put(&1, client_name, categories))
  end

  @spec delete(map()) :: :ok
  def delete(%{"client_name" => client_name, "category" => category} = _subscription) do
    categories =
      Agent.get(__MODULE__, &Map.get(&1, client_name))
      |> Enum.filter(&(&1 != category))

    Agent.update(__MODULE__, &Map.put(&1, client_name, categories))
  end

  @spec list(String.t()) :: [String.t()]
  def list(client_name) do
    Agent.get(__MODULE__, &Map.get(&1, client_name))
  end
end
