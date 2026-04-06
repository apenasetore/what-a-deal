defmodule Gateway.PromoStoreTest do
  use ExUnit.Case

  alias Gateway.PromoStore

  setup do
    start_supervised!(PromoStore)
    :ok
  end

  describe "add/1 e list/0" do
    test "adiciona promocao e lista" do
      promo = %{"id" => "abc-123", "nome" => "Clean Code", "categoria" => "livro"}
      :ok = PromoStore.add(promo)

      assert PromoStore.list() == [promo]
    end

    test "adiciona multiplas promocoes" do
      promo1 = %{"id" => "1", "nome" => "Clean Code", "categoria" => "livro"}
      promo2 = %{"id" => "2", "nome" => "Elixir in Action", "categoria" => "livro"}

      :ok = PromoStore.add(promo1)
      :ok = PromoStore.add(promo2)

      promos = PromoStore.list()
      assert length(promos) == 2
      assert promo1 in promos
      assert promo2 in promos
    end

    test "atualiza promocao com mesmo id" do
      promo_v1 = %{"id" => "1", "nome" => "Clean Code", "preco" => 89.90}
      promo_v2 = %{"id" => "1", "nome" => "Clean Code", "preco" => 45.00}

      :ok = PromoStore.add(promo_v1)
      :ok = PromoStore.add(promo_v2)

      assert PromoStore.list() == [promo_v2]
    end
  end

  describe "get/1" do
    test "retorna promocao pelo id" do
      promo = %{"id" => "abc-123", "nome" => "Clean Code"}
      :ok = PromoStore.add(promo)

      assert PromoStore.get("abc-123") == promo
    end

    test "retorna nil para id inexistente" do
      assert PromoStore.get("nao-existe") == nil
    end
  end

  describe "count/0" do
    test "retorna zero quando vazio" do
      assert PromoStore.count() == 0
    end

    test "retorna numero correto de promocoes" do
      :ok = PromoStore.add(%{"id" => "1", "nome" => "A"})
      :ok = PromoStore.add(%{"id" => "2", "nome" => "B"})

      assert PromoStore.count() == 2
    end
  end

  describe "clear/0" do
    test "remove todas as promocoes" do
      :ok = PromoStore.add(%{"id" => "1", "nome" => "A"})
      :ok = PromoStore.add(%{"id" => "2", "nome" => "B"})

      :ok = PromoStore.clear()

      assert PromoStore.list() == []
      assert PromoStore.count() == 0
    end
  end
end
