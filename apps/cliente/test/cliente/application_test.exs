defmodule Cliente.ApplicationTest do
  use ExUnit.Case, async: false

  doctest Cliente.Application

  alias Cliente.Application, as: ClienteApp

  describe "build_routing_keys/2" do
    test "categorias mapeiam para promocao.categoria.<categoria>" do
      assert ClienteApp.build_routing_keys(["livro", "jogo"], false) ==
               ["promocao.categoria.livro", "promocao.categoria.jogo"]
    end

    test "destaque=true adiciona promocao.categoria.destaque ao final" do
      assert ClienteApp.build_routing_keys(["livro"], true) ==
               ["promocao.categoria.livro", "promocao.categoria.destaque"]
    end

    test "lista vazia + destaque=true" do
      assert ClienteApp.build_routing_keys([], true) == ["promocao.categoria.destaque"]
    end

    test "lista vazia + destaque=false" do
      assert ClienteApp.build_routing_keys([], false) == []
    end
  end

  describe "generate_queue_name/0" do
    test "gera nome com prefixo cliente_" do
      assert "cliente_" <> _ = ClienteApp.generate_queue_name()
    end

    test "gera nomes diferentes em chamadas sucessivas" do
      refute ClienteApp.generate_queue_name() == ClienteApp.generate_queue_name()
    end
  end

  describe "rabbitmq_url/0" do
    test "retorna valor de RABBITMQ_URL quando setado" do
      System.put_env("RABBITMQ_URL", "amqp://test:test@example.com")

      assert ClienteApp.rabbitmq_url() == "amqp://test:test@example.com"

      System.delete_env("RABBITMQ_URL")
    end

    test "retorna default quando RABBITMQ_URL nao esta setado" do
      System.delete_env("RABBITMQ_URL")

      assert ClienteApp.rabbitmq_url() == "amqp://guest:guest@localhost"
    end
  end

  describe "rabbitmq_name/0" do
    test "retorna :cliente_rabbitmq" do
      assert ClienteApp.rabbitmq_name() == :cliente_rabbitmq
    end
  end

  describe "categorias/0" do
    setup do
      original = Application.get_env(:cliente, :categorias)
      on_exit(fn -> restore_env(:categorias, original) end)
      System.delete_env("CLIENTE_CATEGORIAS")
      :ok
    end

    test "retorna config quando env var nao setado" do
      Application.put_env(:cliente, :categorias, ["livro", "jogo"])
      assert ClienteApp.categorias() == ["livro", "jogo"]
    end

    test "env var sobrepoe config" do
      Application.put_env(:cliente, :categorias, ["livro"])
      System.put_env("CLIENTE_CATEGORIAS", "jogo,eletronico")

      assert ClienteApp.categorias() == ["jogo", "eletronico"]
    after
      System.delete_env("CLIENTE_CATEGORIAS")
    end

    test "env var aceita espacos no CSV" do
      System.put_env("CLIENTE_CATEGORIAS", "livro, jogo , eletronico")
      assert ClienteApp.categorias() == ["livro", "jogo", "eletronico"]
    after
      System.delete_env("CLIENTE_CATEGORIAS")
    end

    test "env var vazia cai pro config" do
      Application.put_env(:cliente, :categorias, ["livro"])
      System.put_env("CLIENTE_CATEGORIAS", "")
      assert ClienteApp.categorias() == ["livro"]
    after
      System.delete_env("CLIENTE_CATEGORIAS")
    end

    test "default vazio quando nem env var nem config" do
      Application.delete_env(:cliente, :categorias)
      assert ClienteApp.categorias() == []
    end
  end

  describe "destaque?/0" do
    setup do
      original = Application.get_env(:cliente, :destaque)
      on_exit(fn -> restore_env(:destaque, original) end)
      System.delete_env("CLIENTE_DESTAQUE")
      :ok
    end

    test "retorna config quando env var nao setado" do
      Application.put_env(:cliente, :destaque, true)
      assert ClienteApp.destaque?() == true
    end

    test "env var 'true' sobrepoe config false" do
      Application.put_env(:cliente, :destaque, false)
      System.put_env("CLIENTE_DESTAQUE", "true")
      assert ClienteApp.destaque?() == true
    after
      System.delete_env("CLIENTE_DESTAQUE")
    end

    test "env var 'false' sobrepoe config true" do
      Application.put_env(:cliente, :destaque, true)
      System.put_env("CLIENTE_DESTAQUE", "false")
      assert ClienteApp.destaque?() == false
    after
      System.delete_env("CLIENTE_DESTAQUE")
    end

    test "default false quando nem env var nem config" do
      Application.delete_env(:cliente, :destaque)
      assert ClienteApp.destaque?() == false
    end
  end

  describe "autostart?/0" do
    setup do
      original = Application.get_env(:cliente, :autostart)
      on_exit(fn -> restore_env(:autostart, original) end)
      System.delete_env("CLIENTE_AUTOSTART")
      :ok
    end

    test "retorna config quando env var nao setado" do
      Application.put_env(:cliente, :autostart, false)
      assert ClienteApp.autostart?() == false
    end

    test "env var 'true' sobrepoe config false" do
      Application.put_env(:cliente, :autostart, false)
      System.put_env("CLIENTE_AUTOSTART", "true")
      assert ClienteApp.autostart?() == true
    after
      System.delete_env("CLIENTE_AUTOSTART")
    end

    test "default true quando nem env var nem config" do
      Application.delete_env(:cliente, :autostart)
      assert ClienteApp.autostart?() == true
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:cliente, key)
  defp restore_env(key, value), do: Application.put_env(:cliente, key, value)
end
