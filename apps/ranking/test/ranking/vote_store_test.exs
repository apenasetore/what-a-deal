defmodule Ranking.VoteStoreTest do
  use ExUnit.Case, async: false

  alias Ranking.VoteStore

  setup do
    start_supervised!(VoteStore)
    %{promo_id: unique_id()}
  end

  describe "vote/2" do
    test "voto positivo aumenta o score em 1", %{promo_id: id} do
      assert VoteStore.vote(id, 1) == 1
    end

    test "voto negativo diminui o score em 1", %{promo_id: id} do
      assert VoteStore.vote(id, -1) == -1
    end

    test "voto zero nao altera o score", %{promo_id: id} do
      VoteStore.vote(id, 1)
      assert VoteStore.vote(id, 0) == 1
    end

    test "votos acumulam", %{promo_id: id} do
      VoteStore.vote(id, 1)
      VoteStore.vote(id, 1)
      VoteStore.vote(id, 1)
      assert VoteStore.vote(id, -1) == 2
    end

    test "estados isolados por promo_id" do
      id1 = unique_id()
      id2 = unique_id()

      VoteStore.vote(id1, 1)
      VoteStore.vote(id1, 1)
      VoteStore.vote(id2, -1)

      assert VoteStore.vote(id1, 0) == 2
      assert VoteStore.vote(id2, 0) == -1
    end
  end

  describe "destaque?/1" do
    test "retorna false para promo nova", %{promo_id: id} do
      refute VoteStore.destaque?(id)
    end

    test "retorna false antes de marcar_destaque", %{promo_id: id} do
      VoteStore.vote(id, 1)
      VoteStore.vote(id, 1)
      refute VoteStore.destaque?(id)
    end

    test "retorna true apos marcar_destaque", %{promo_id: id} do
      VoteStore.vote(id, 1)
      VoteStore.marcar_destaque(id)
      assert VoteStore.destaque?(id)
    end
  end

  describe "marcar_destaque/1" do
    test "marca promo existente como destaque", %{promo_id: id} do
      VoteStore.vote(id, 1)
      VoteStore.marcar_destaque(id)
      assert VoteStore.destaque?(id)
    end

    test "marca promo nunca votada como destaque", %{promo_id: id} do
      VoteStore.marcar_destaque(id)
      assert VoteStore.destaque?(id)
    end

    test "preserva contagem de votos", %{promo_id: id} do
      VoteStore.vote(id, 1)
      VoteStore.vote(id, 1)
      VoteStore.marcar_destaque(id)
      assert VoteStore.vote(id, 0) == 2
    end

    test "marcacao e idempotente", %{promo_id: id} do
      VoteStore.marcar_destaque(id)
      VoteStore.marcar_destaque(id)
      assert VoteStore.destaque?(id)
    end
  end

  defp unique_id do
    "promo_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end
end
