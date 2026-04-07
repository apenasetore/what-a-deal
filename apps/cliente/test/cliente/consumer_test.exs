defmodule Cliente.ConsumerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Cliente.Consumer
  alias Shared.Crypto
  alias Shared.Event

  describe "handle_message/2 — notificacao do MS Notificacao" do
    test "exibe notificacao 'nova' com dados da promocao" do
      notif = %{
        "tipo" => "nova",
        "categoria" => "livro",
        "promo_id" => "abc-123",
        "source" => "promocao",
        "timestamp" => "2026-04-07T15:30:22Z",
        "promo" => %{
          "nome" => "Clean Code",
          "loja" => "Amazon",
          "preco_original" => 89.9,
          "preco_promocional" => 45.0
        }
      }

      output =
        capture_io(fn ->
          Consumer.handle_message("promocao.livro", Jason.encode!(notif))
        end)

      assert output =~ "[livro]"
      assert output =~ "Nova promocao"
      assert output =~ "Clean Code"
      assert output =~ "Amazon"
      assert output =~ "R$89.90"
      assert output =~ "R$45.00"
      refute output =~ "HOT DEAL"
    end

    test "exibe notificacao 'hot deal' com label HOT DEAL" do
      notif = %{
        "tipo" => "hot deal",
        "categoria" => "livro",
        "promo_id" => "abc-123",
        "source" => "ranking",
        "timestamp" => "2026-04-07T15:31:05Z",
        "promo" => %{"nome" => "Clean Code"}
      }

      output =
        capture_io(fn ->
          Consumer.handle_message("promocao.livro", Jason.encode!(notif))
        end)

      assert output =~ "[livro]"
      assert output =~ "HOT DEAL"
      assert output =~ "Clean Code"
      refute output =~ "Nova promocao"
    end

    test "ignora payload JSON invalido sem crashar" do
      output =
        capture_io(fn ->
          assert :ok = Consumer.handle_message("promocao.livro", "isso nao e json")
        end)

      refute output =~ "Nova promocao"
      refute output =~ "HOT DEAL"
    end

    test "extrai categoria do routing key quando ausente no payload" do
      notif = %{"tipo" => "nova", "promo" => %{"nome" => "X"}}

      output =
        capture_io(fn ->
          Consumer.handle_message("promocao.jogo", Jason.encode!(notif))
        end)

      assert output =~ "[jogo]"
    end
  end

  describe "handle_message/2 — promocao.destaque (envelope do Ranking)" do
    test "exibe destaque a partir de envelope assinado" do
      {ranking_priv, _} = Crypto.generate_key_pair()

      promo = %{
        "id" => "promo-42",
        "nome" => "Clean Code",
        "categoria" => "livro",
        "loja" => "Amazon",
        "preco_original" => 89.90,
        "preco_promocional" => 45.00
      }

      json =
        Event.new("promocao.destaque", promo, "ranking")
        |> Event.sign(ranking_priv)
        |> Event.Envelope.encode()
        |> elem(1)

      output =
        capture_io(fn ->
          assert :ok = Consumer.handle_message("promocao.destaque", json)
        end)

      assert output =~ "[livro]"
      assert output =~ "HOT DEAL"
      assert output =~ "Clean Code"
      assert output =~ "Amazon"
      assert output =~ "R$89.90"
      assert output =~ "R$45.00"
    end

    test "ignora envelope invalido sem crashar" do
      output =
        capture_io(fn ->
          assert :ok = Consumer.handle_message("promocao.destaque", "lixo")
        end)

      refute output =~ "HOT DEAL"
    end
  end

  describe "display_notificacao/2" do
    test "label 'HOT DEAL' quando tipo='hot deal'" do
      output =
        capture_io(fn ->
          Consumer.display_notificacao("promocao.livro", %{
            "tipo" => "hot deal",
            "categoria" => "livro",
            "promo" => %{"nome" => "X"}
          })
        end)

      assert output =~ "HOT DEAL"
    end

    test "label 'Nova promocao' quando tipo='nova'" do
      output =
        capture_io(fn ->
          Consumer.display_notificacao("promocao.livro", %{
            "tipo" => "nova",
            "categoria" => "livro",
            "promo" => %{"nome" => "X"}
          })
        end)

      assert output =~ "Nova promocao"
    end
  end
end
