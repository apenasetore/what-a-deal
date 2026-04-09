defmodule Ranking.VoteStore do
  @moduledoc """
  Armazena contagem de votos por promocao usando Agent.

  Mantem um mapa `%{promo_id => %{up: n, down: n, destaque: boolean}}`
  em memoria.
  """

  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc "Registra um voto (+1 ou -1) para uma promocao. Retorna o score atualizado."
  @spec vote(String.t(), integer()) :: integer()
  def vote(promo_id, voto) do
    Agent.get_and_update(__MODULE__, fn state ->
      entry = entry(state, promo_id)

      entry =
        cond do
          voto > 0 -> %{entry | up: entry.up + 1}
          voto < 0 -> %{entry | down: entry.down + 1}
          true -> entry
        end

      score = entry.up - entry.down
      {score, Map.put(state, promo_id, entry)}
    end)
  end

  @doc "Retorna true se a promocao ja foi marcada como destaque."
  @spec destaque?(String.t()) :: boolean()
  def destaque?(promo_id) do
    Agent.get(__MODULE__, fn state -> entry(state, promo_id).destaque end)
  end

  @doc "Marca uma promocao como destaque (evita publicar destaque duplicado)."
  @spec marcar_destaque(String.t()) :: :ok
  def marcar_destaque(promo_id) do
    Agent.update(__MODULE__, fn state ->
      Map.put(state, promo_id, %{entry(state, promo_id) | destaque: true})
    end)
  end

  defp entry(state, promo_id), do: Map.get(state, promo_id, default_entry())

  defp default_entry, do: %{up: 0, down: 0, destaque: false}
end
