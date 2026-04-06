defmodule Shared.CryptoTest do
  use ExUnit.Case, async: true

  alias Shared.Crypto

  describe "generate_key_pair/0" do
    test "retorna uma tupla {private_key, public_key}" do
      {priv, pub} = Crypto.generate_key_pair()

      # Chave privada e uma record :RSAPrivateKey (tupla com tag na posicao 0)
      assert elem(priv, 0) == :RSAPrivateKey

      # Chave publica e uma record :RSAPublicKey
      assert elem(pub, 0) == :RSAPublicKey
    end

    test "gera chaves diferentes a cada chamada" do
      {priv1, _pub1} = Crypto.generate_key_pair()
      {priv2, _pub2} = Crypto.generate_key_pair()

      # Modulus (elem 2) deve ser diferente entre chaves distintas
      assert elem(priv1, 2) != elem(priv2, 2)
    end

    test "chave publica corresponde a chave privada" do
      {priv, pub} = Crypto.generate_key_pair()

      # Modulus e expoente publico devem ser iguais
      assert elem(priv, 2) == elem(pub, 1)
      assert elem(priv, 3) == elem(pub, 2)
    end
  end

  describe "sign/2 e verify/3" do
    setup do
      {priv, pub} = Crypto.generate_key_pair()
      %{private_key: priv, public_key: pub}
    end

    test "assinatura valida retorna true", %{private_key: priv, public_key: pub} do
      payload = "dados do evento"
      signature = Crypto.sign(payload, priv)

      assert Crypto.verify(payload, signature, pub)
    end

    test "payload alterado invalida a assinatura", %{private_key: priv, public_key: pub} do
      signature = Crypto.sign("payload original", priv)

      refute Crypto.verify("payload alterado", signature, pub)
    end

    test "assinatura de outra chave e rejeitada", %{private_key: priv} do
      {_outra_priv, outra_pub} = Crypto.generate_key_pair()

      signature = Crypto.sign("payload", priv)

      refute Crypto.verify("payload", signature, outra_pub)
    end

    test "assinatura corrompida e rejeitada", %{private_key: priv, public_key: pub} do
      payload = "dados do evento"
      signature = Crypto.sign(payload, priv)

      # Corrompe um byte da assinatura
      <<primeiro_byte, resto::binary>> = signature
      assinatura_corrompida = <<primeiro_byte + 1, resto::binary>>

      refute Crypto.verify(payload, assinatura_corrompida, pub)
    end

    test "assina payloads vazios", %{private_key: priv, public_key: pub} do
      signature = Crypto.sign("", priv)

      assert Crypto.verify("", signature, pub)
      refute Crypto.verify("nao vazio", signature, pub)
    end

    test "assinatura tem 256 bytes (RSA 2048 bits)", %{private_key: priv} do
      signature = Crypto.sign("qualquer payload", priv)

      assert byte_size(signature) == 256
    end
  end

  describe "save_keys/3 e load_private_key/1 e load_public_key/1" do
    setup do
      {priv, pub} = Crypto.generate_key_pair()

      # Usa um nome unico para evitar colisao entre testes paralelos
      service_name = "test_service_#{System.unique_integer([:positive])}"

      on_exit(fn ->
        # Limpa os arquivos de chave criados pelo teste
        dir = Path.join([:code.priv_dir(:shared), "keys", service_name])
        File.rm_rf(dir)
      end)

      %{private_key: priv, public_key: pub, service_name: service_name}
    end

    test "salva e carrega chave privada", %{
      private_key: priv,
      public_key: pub,
      service_name: name
    } do
      assert :ok = Crypto.save_keys(name, priv, pub)

      {:ok, loaded_priv} = Crypto.load_private_key(name)
      assert loaded_priv == priv
    end

    test "salva e carrega chave publica", %{
      private_key: priv,
      public_key: pub,
      service_name: name
    } do
      Crypto.save_keys(name, priv, pub)

      {:ok, loaded_pub} = Crypto.load_public_key(name)
      assert loaded_pub == pub
    end

    test "chave carregada do disco funciona para sign/verify", %{
      private_key: priv,
      public_key: pub,
      service_name: name
    } do
      Crypto.save_keys(name, priv, pub)

      {:ok, loaded_priv} = Crypto.load_private_key(name)
      {:ok, loaded_pub} = Crypto.load_public_key(name)

      payload = "evento de teste"
      signature = Crypto.sign(payload, loaded_priv)

      assert Crypto.verify(payload, signature, loaded_pub)
    end

    test "retorna erro ao carregar chave de servico inexistente" do
      assert {:error, :enoent} = Crypto.load_private_key("servico_inexistente")
      assert {:error, :enoent} = Crypto.load_public_key("servico_inexistente")
    end
  end
end
