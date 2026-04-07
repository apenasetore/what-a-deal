defmodule Ranking.VoteStore do
  @moduledoc """
  Armazena contagem de votos por promocao usando Agent.

  Mantém um mapa %{promo_id => %{up: n, down: n}} em memoria.
  """

  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc "Registra um voto (+1 ou -1) para uma promocao. Retorna o score atualizado."
  @spec vote(String.t(), integer()) :: integer()
  def vote(promo_id, voto) do
    Agent.get_and_update(__MODULE__, fn state ->
      entry = Map.get(state, promo_id, %{up: 0, down: 0, destaque: false})

      entry =
        case voto do
          v when v > 0 -> %{entry | up: entry.up + 1}
          v when v < 0 -> %{entry | down: entry.down + 1}
          _ -> entry
        end

      score = entry.up - entry.down
      {score, Map.put(state, promo_id, entry)}
    end)
  end

  @doc "Retorna o score atual de uma promocao (up - down)."
  @spec score(String.t()) :: integer()
  def score(promo_id) do
    Agent.get(__MODULE__, fn state ->
      entry = Map.get(state, promo_id, %{up: 0, down: 0, destaque: false})
      entry.up - entry.down
    end)
  end

  @doc "Retorna true se a promocao ja foi marcada como destaque."
  @spec destaque?(String.t()) :: boolean()
  def destaque?(promo_id) do
    Agent.get(__MODULE__, fn state ->
      entry = Map.get(state, promo_id, %{up: 0, down: 0, destaque: false})
      entry.destaque
    end)
  end

  @doc "Marca uma promocao como destaque (evita publicar destaque duplicado)."
  @spec marcar_destaque(String.t()) :: :ok
  def marcar_destaque(promo_id) do
    Agent.update(__MODULE__, fn state ->
      entry = Map.get(state, promo_id, %{up: 0, down: 0, destaque: false})
      Map.put(state, promo_id, %{entry | destaque: true})
    end)
  end
end
