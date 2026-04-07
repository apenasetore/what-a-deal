defmodule Promocao.ApplicationTest do
  use ExUnit.Case, async: false

  alias Promocao.Application, as: PromocaoApp

  describe "constantes do modulo" do
    test "rabbitmq_name e :promocao_rabbitmq" do
      assert PromocaoApp.rabbitmq_name() == :promocao_rabbitmq
    end

    test "queue e 'fila_promocao'" do
      assert PromocaoApp.queue() == "fila_promocao"
    end

    test "routing_keys contem promocao.recebida" do
      assert "promocao.recebida" in PromocaoApp.routing_keys()
    end
  end

  describe "rabbitmq_url/0" do
    test "retorna valor de RABBITMQ_URL quando setado" do
      System.put_env("RABBITMQ_URL", "amqp://test:test@example.com")

      assert PromocaoApp.rabbitmq_url() == "amqp://test:test@example.com"

      System.delete_env("RABBITMQ_URL")
    end

    test "retorna default quando RABBITMQ_URL nao esta setado" do
      System.delete_env("RABBITMQ_URL")

      assert PromocaoApp.rabbitmq_url() == "amqp://guest:guest@localhost"
    end
  end
end
