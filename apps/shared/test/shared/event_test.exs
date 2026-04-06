defmodule Shared.EventTest do
  use ExUnit.Case, async: true

  alias Shared.Crypto
  alias Shared.Event

  describe "new/3" do
    test "cria evento com campos preenchidos" do
      event = Event.new("promocao.recebida", %{"nome" => "Clean Code"}, "gateway")

      assert event.type == "promocao.recebida"
      assert event.payload == %{"nome" => "Clean Code"}
      assert event.source == "gateway"
      assert event.signature == nil
    end

    test "gera UUID no campo id" do
      event = Event.new("promocao.recebida", %{}, "gateway")

      # UUID v4: 8-4-4-4-12 caracteres hex
      assert event.id =~ ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
    end

    test "gera IDs unicos a cada chamada" do
      event1 = Event.new("promocao.recebida", %{}, "gateway")
      event2 = Event.new("promocao.recebida", %{}, "gateway")

      assert event1.id != event2.id
    end

    test "preenche timestamp com DateTime UTC" do
      before = DateTime.utc_now()
      event = Event.new("promocao.recebida", %{}, "gateway")
      after_time = DateTime.utc_now()

      assert DateTime.compare(event.timestamp, before) in [:gt, :eq]
      assert DateTime.compare(event.timestamp, after_time) in [:lt, :eq]
    end
  end

  describe "sign/2 e verify/2" do
    setup do
      {priv, pub} = Crypto.generate_key_pair()
      %{private_key: priv, public_key: pub}
    end

    test "assina evento e preenche campo signature", %{private_key: priv} do
      event = Event.new("promocao.recebida", %{"nome" => "Clean Code"}, "gateway")
      signed = Event.sign(event, priv)

      assert signed.signature != nil
      assert is_binary(signed.signature)
      assert byte_size(signed.signature) == 256
    end

    test "nao altera outros campos ao assinar", %{private_key: priv} do
      event = Event.new("promocao.recebida", %{"nome" => "Clean Code"}, "gateway")
      signed = Event.sign(event, priv)

      assert signed.id == event.id
      assert signed.type == event.type
      assert signed.payload == event.payload
      assert signed.source == event.source
      assert signed.timestamp == event.timestamp
    end

    test "evento assinado e verificado com sucesso", %{private_key: priv, public_key: pub} do
      event = Event.new("promocao.recebida", %{"nome" => "Clean Code"}, "gateway")
      signed = Event.sign(event, priv)

      assert Event.verify(signed, pub)
    end

    test "rejeita evento com payload alterado apos assinatura", %{
      private_key: priv,
      public_key: pub
    } do
      event = Event.new("promocao.recebida", %{"nome" => "Clean Code"}, "gateway")
      signed = Event.sign(event, priv)

      # Altera o payload depois de assinar
      tampered = %{signed | payload: %{"nome" => "Outro Livro"}}

      refute Event.verify(tampered, pub)
    end

    test "rejeita evento com type alterado apos assinatura", %{
      private_key: priv,
      public_key: pub
    } do
      event = Event.new("promocao.recebida", %{"nome" => "Clean Code"}, "gateway")
      signed = Event.sign(event, priv)

      tampered = %{signed | type: "promocao.voto"}

      refute Event.verify(tampered, pub)
    end

    test "rejeita evento com source alterado apos assinatura", %{
      private_key: priv,
      public_key: pub
    } do
      event = Event.new("promocao.recebida", %{"nome" => "Clean Code"}, "gateway")
      signed = Event.sign(event, priv)

      tampered = %{signed | source: "ranking"}

      refute Event.verify(tampered, pub)
    end

    test "rejeita evento verificado com chave publica errada", %{private_key: priv} do
      {_outra_priv, outra_pub} = Crypto.generate_key_pair()

      event = Event.new("promocao.recebida", %{"nome" => "Clean Code"}, "gateway")
      signed = Event.sign(event, priv)

      refute Event.verify(signed, outra_pub)
    end
  end

  describe "signable_payload/1" do
    test "retorna JSON string" do
      event = Event.new("promocao.recebida", %{"nome" => "Clean Code"}, "gateway")
      signable = Event.signable_payload(event)

      assert is_binary(signable)
      assert {:ok, _} = Jason.decode(signable)
    end

    test "nao inclui campo signature" do
      event = Event.new("promocao.recebida", %{"nome" => "Clean Code"}, "gateway")
      signable = Event.signable_payload(event)
      {:ok, map} = Jason.decode(signable)

      refute Map.has_key?(map, "signature")
    end

    test "inclui todos os outros campos" do
      event = Event.new("promocao.recebida", %{"nome" => "Clean Code"}, "gateway")
      signable = Event.signable_payload(event)
      {:ok, map} = Jason.decode(signable)

      assert Map.has_key?(map, "id")
      assert Map.has_key?(map, "type")
      assert Map.has_key?(map, "payload")
      assert Map.has_key?(map, "source")
      assert Map.has_key?(map, "timestamp")
    end

    test "e deterministico — mesma entrada gera mesma saida" do
      event = Event.new("promocao.recebida", %{"nome" => "Clean Code"}, "gateway")

      assert Event.signable_payload(event) == Event.signable_payload(event)
    end
  end

  describe "generate_uuid/0" do
    test "gera UUID v4 valido" do
      uuid = Event.generate_uuid()

      assert uuid =~ ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
    end

    test "gera UUIDs unicos" do
      uuids = for _ <- 1..100, do: Event.generate_uuid()

      assert length(Enum.uniq(uuids)) == 100
    end
  end
end
