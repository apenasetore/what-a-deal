defmodule Notificacao.ApplicationTest do
  use ExUnit.Case, async: false

  alias Notificacao.Application, as: NotificacaoApp

  describe "constantes do modulo" do
    test "rabbitmq_name e :notificacao_rabbitmq" do
      assert NotificacaoApp.rabbitmq_name() == :notificacao_rabbitmq
    end

    test "queue e 'fila_notificacao'" do
      assert NotificacaoApp.queue() == "fila_notificacao"
    end

    test "routing_keys contem promocao.publicada" do
      assert "promocao.publicada" in NotificacaoApp.routing_keys()
    end

    test "routing_keys contem promocao.categoria.destaque" do
      assert "promocao.categoria.destaque" in NotificacaoApp.routing_keys()
    end
  end

  describe "rabbitmq_url/0" do
    test "retorna valor de RABBITMQ_URL quando setado" do
      System.put_env("RABBITMQ_URL", "amqp://test:test@example.com")

      assert NotificacaoApp.rabbitmq_url() == "amqp://test:test@example.com"

      System.delete_env("RABBITMQ_URL")
    end

    test "retorna default quando RABBITMQ_URL nao esta setado" do
      System.delete_env("RABBITMQ_URL")

      assert NotificacaoApp.rabbitmq_url() == "amqp://guest:guest@localhost"
    end
  end
end
