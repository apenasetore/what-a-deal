defmodule Shared.Event.EnvelopeTest do
  use ExUnit.Case, async: true

  alias Shared.Crypto
  alias Shared.Event
  alias Shared.Event.Envelope

  setup do
    {priv, pub} = Crypto.generate_key_pair()

    event =
      Event.new("promocao.recebida", %{"nome" => "Clean Code", "preco" => 45.0}, "gateway")
      |> Event.sign(priv)

    %{event: event, private_key: priv, public_key: pub}
  end

  describe "encode/1" do
    test "retorna JSON valido", %{event: event} do
      {:ok, json} = Envelope.encode(event)

      assert is_binary(json)
      assert {:ok, _} = Jason.decode(json)
    end

    test "signature e codificada em Base64", %{event: event} do
      {:ok, json} = Envelope.encode(event)
      {:ok, map} = Jason.decode(json)

      # Deve ser uma string Base64 valida
      assert is_binary(map["signature"])
      assert {:ok, _} = Base.decode64(map["signature"])
    end

    test "timestamp e codificado em ISO 8601", %{event: event} do
      {:ok, json} = Envelope.encode(event)
      {:ok, map} = Jason.decode(json)

      assert {:ok, _, _} = DateTime.from_iso8601(map["timestamp"])
    end

    test "preserva todos os campos do evento", %{event: event} do
      {:ok, json} = Envelope.encode(event)
      {:ok, map} = Jason.decode(json)

      assert map["id"] == event.id
      assert map["type"] == event.type
      assert map["payload"] == event.payload
      assert map["source"] == event.source
    end
  end

  describe "decode/1" do
    test "reconstroi o evento a partir do JSON", %{event: event} do
      {:ok, json} = Envelope.encode(event)
      {:ok, decoded} = Envelope.decode(json)

      assert decoded.id == event.id
      assert decoded.type == event.type
      assert decoded.payload == event.payload
      assert decoded.source == event.source
      assert decoded.signature == event.signature
      assert DateTime.compare(decoded.timestamp, event.timestamp) == :eq
    end

    test "retorna erro para JSON invalido" do
      assert {:error, _} = Envelope.decode("isso nao e json")
    end

    test "retorna erro para signature Base64 invalida" do
      json =
        Jason.encode!(%{
          "id" => "abc",
          "type" => "test",
          "payload" => %{},
          "source" => "test",
          "signature" => "!!!nao-e-base64!!!",
          "timestamp" => DateTime.to_iso8601(DateTime.utc_now())
        })

      assert {:error, _} = Envelope.decode(json)
    end

    test "retorna erro para timestamp invalido" do
      json =
        Jason.encode!(%{
          "id" => "abc",
          "type" => "test",
          "payload" => %{},
          "source" => "test",
          "signature" => Base.encode64("fake"),
          "timestamp" => "nao-e-data"
        })

      assert {:error, _} = Envelope.decode(json)
    end
  end

  describe "encode/1 + decode/1 round-trip" do
    test "evento sobrevive ao round-trip encode -> decode", %{event: event} do
      {:ok, json} = Envelope.encode(event)
      {:ok, decoded} = Envelope.decode(json)

      assert decoded.id == event.id
      assert decoded.type == event.type
      assert decoded.payload == event.payload
      assert decoded.source == event.source
      assert decoded.signature == event.signature
    end

    test "assinatura permanece valida apos round-trip", %{event: event, public_key: pub} do
      {:ok, json} = Envelope.encode(event)
      {:ok, decoded} = Envelope.decode(json)

      assert Event.verify(decoded, pub)
    end

    test "payload complexo sobrevive ao round-trip", %{private_key: priv, public_key: pub} do
      payload = %{
        "nome" => "Clean Code",
        "preco_original" => 89.90,
        "preco_promocional" => 45.00,
        "categoria" => "livro",
        "loja" => "Amazon",
        "tags" => ["programacao", "boas praticas"]
      }

      event =
        Event.new("promocao.recebida", payload, "gateway")
        |> Event.sign(priv)

      {:ok, json} = Envelope.encode(event)
      {:ok, decoded} = Envelope.decode(json)

      assert decoded.payload == payload
      assert Event.verify(decoded, pub)
    end
  end
end
