defmodule Shared.Crypto do
  @moduledoc """
  Assinatura digital RSA para autenticacao entre microsservicos.

  Cada microsservico possui um par de chaves RSA (2048 bits) armazenado
  em formato PEM no diretorio `priv/keys/<service_name>/`. A chave privada
  e usada para assinar eventos antes de publica-los no RabbitMQ, e a chave
  publica e usada pelos consumidores para verificar autenticidade e integridade.

  ## Fluxo tipico

      # Setup (uma vez por servico):
      {priv, pub} = Shared.Crypto.generate_key_pair()
      Shared.Crypto.save_keys("gateway", priv, pub)

      # Publicacao (produtor assina):
      {:ok, priv} = Shared.Crypto.load_private_key("gateway")
      signature = Shared.Crypto.sign(payload, priv)

      # Consumo (consumidor verifica):
      {:ok, pub} = Shared.Crypto.load_public_key("gateway")
      true = Shared.Crypto.verify(payload, signature, pub)

  ## Algoritmo

  Utiliza RSA 2048 bits com SHA-256 (RSASSA-PKCS1-v1_5), via modulos
  `:public_key` e `:crypto` da stdlib do Erlang/OTP.
  """

  require Record

  Record.defrecord(
    :rsa_private_key,
    :RSAPrivateKey,
    Record.extract(:RSAPrivateKey, from_lib: "public_key/include/public_key.hrl")
  )

  Record.defrecord(
    :rsa_public_key,
    :RSAPublicKey,
    Record.extract(:RSAPublicKey, from_lib: "public_key/include/public_key.hrl")
  )

  @type private_key :: :public_key.rsa_private_key()
  @type public_key :: :public_key.rsa_public_key()

  @doc """
  Gera um par de chaves RSA de 2048 bits.

  Retorna `{private_key, public_key}`, onde ambas sao records Erlang
  (`:RSAPrivateKey` e `:RSAPublicKey`).

  ## Exemplo

      {priv, pub} = Shared.Crypto.generate_key_pair()
  """
  @spec generate_key_pair() :: {private_key(), public_key()}
  def generate_key_pair do
    private_key = :public_key.generate_key({:rsa, 2048, 65_537})
    {private_key, extract_public_key(private_key)}
  end

  defp extract_public_key(private_key) do
    rsa_public_key(
      modulus: rsa_private_key(private_key, :modulus),
      publicExponent: rsa_private_key(private_key, :publicExponent)
    )
  end

  @doc """
  Persiste um par de chaves em formato PEM.

  Cria o diretorio `priv/keys/<service_name>/` e salva dois arquivos:
  - `private.pem` — chave privada em formato PKCS#1
  - `public.pem` — chave publica em formato X.509/SPKI

  ## Exemplo

      Shared.Crypto.save_keys("gateway", private_key, public_key)
  """
  @spec save_keys(String.t(), private_key(), public_key()) :: :ok
  def save_keys(service_name, private_key, public_key) do
    dir = keys_dir(service_name)
    File.mkdir_p!(dir)

    # Chave privada -> PEM
    private_pem_entry = :public_key.pem_entry_encode(:RSAPrivateKey, private_key)
    private_pem = :public_key.pem_encode([private_pem_entry])
    File.write!(Path.join(dir, "private.pem"), private_pem)

    # Chave pública -> PEM
    public_pem_entry = :public_key.pem_entry_encode(:SubjectPublicKeyInfo, public_key)
    public_pem = :public_key.pem_encode([public_pem_entry])
    File.write!(Path.join(dir, "public.pem"), public_pem)

    :ok
  end

  defp keys_dir(service_name) do
    Path.join([:code.priv_dir(:shared), "keys", service_name])
  end

  @doc """
  Carrega a chave privada de um microsservico a partir do arquivo PEM.

  Retorna `{:ok, private_key}` ou `{:error, reason}` se o arquivo nao
  existir ou o conteudo for invalido.

  ## Exemplo

      {:ok, priv} = Shared.Crypto.load_private_key("gateway")
  """
  @spec load_private_key(String.t()) :: {:ok, private_key()} | {:error, term()}
  def load_private_key(service_name) do
    path = Path.join(keys_dir(service_name), "private.pem")

    with {:ok, pem_binary} <- File.read(path),
         [pem_entry] <- :public_key.pem_decode(pem_binary),
         private_key <- :public_key.pem_entry_decode(pem_entry) do
      {:ok, private_key}
    else
      {:error, reason} -> {:error, reason}
      [] -> {:error, :invalid_pem}
    end
  end

  @doc """
  Carrega a chave publica de um microsservico a partir do arquivo PEM.

  Retorna `{:ok, public_key}` ou `{:error, reason}` se o arquivo nao
  existir ou o conteudo for invalido.

  ## Exemplo

      {:ok, pub} = Shared.Crypto.load_public_key("gateway")
  """
  @spec load_public_key(String.t()) :: {:ok, public_key()} | {:error, term()}
  def load_public_key(service_name) do
    path = Path.join(keys_dir(service_name), "public.pem")

    with {:ok, pem_binary} <- File.read(path),
         [pem_entry] <- :public_key.pem_decode(pem_binary),
         public_key <- :public_key.pem_entry_decode(pem_entry) do
      {:ok, public_key}
    else
      {:error, reason} -> {:error, reason}
      [] -> {:error, :invalid_pem}
    end
  end

  @doc """
  Assina um payload binario usando SHA-256 com RSA (RSASSA-PKCS1-v1_5).

  Retorna a assinatura como binario de 256 bytes.

  ## Exemplo

      signature = Shared.Crypto.sign("dados do evento", private_key)
  """
  @spec sign(binary(), private_key()) :: binary()
  def sign(payload, private_key) do
    :public_key.sign(payload, :sha256, private_key)
  end

  @doc """
  Verifica se a assinatura corresponde ao payload, usando a chave publica.

  Retorna `true` se a assinatura e valida, `false` caso contrario.
  Uma assinatura invalida indica que o payload foi alterado ou que foi
  assinado por uma chave privada diferente.

  ## Exemplo

      true = Shared.Crypto.verify("dados do evento", signature, public_key)
  """
  @spec verify(binary(), binary(), public_key()) :: boolean()
  def verify(payload, signature, public_key) do
    :public_key.verify(payload, :sha256, signature, public_key)
  end
end
