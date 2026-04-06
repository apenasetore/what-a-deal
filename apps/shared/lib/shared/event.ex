defmodule Shared.Event do
  @moduledoc """
  Struct padrao para todos os eventos do sistema.

  Representa um evento que trafega entre microsservicos via RabbitMQ.
  Contem os dados do evento (`payload`), metadados de roteamento (`type`, `source`)
  e a assinatura digital para garantir autenticidade e integridade.

  ## Ciclo de vida de um evento

      # 1. Criar (signature = nil)
      event = Shared.Event.new("promocao.recebida", %{"nome" => "Clean Code"}, "gateway")

      # 2. Assinar (preenche signature)
      signed = Shared.Event.sign(event, private_key)

      # 3. Serializar e publicar no RabbitMQ (via Envelope)
      {:ok, json} = Shared.Event.Envelope.encode(signed)

      # 4. Consumir, deserializar e verificar
      {:ok, event} = Shared.Event.Envelope.decode(json)
      true = Shared.Event.verify(event, public_key)

  ## Payload canonico

  Para assinar e verificar, o evento e convertido para uma representacao
  JSON deterministica contendo todos os campos exceto `signature`. Isso
  garante que produtor e consumidor concordam sobre o que foi assinado.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          type: String.t(),
          payload: map(),
          source: String.t(),
          signature: binary() | nil,
          timestamp: DateTime.t()
        }

  @enforce_keys [:id, :type, :payload, :source, :timestamp]
  defstruct [:id, :type, :payload, :source, :signature, :timestamp]

  @doc """
  Cria um novo evento com UUID e timestamp gerados automaticamente.

  O campo `signature` inicia como `nil` — use `sign/2` para assinar.

  ## Parametros

  - `type` — routing key do RabbitMQ (ex: `"promocao.recebida"`)
  - `payload` — dados do evento como map
  - `source` — nome do microsservico de origem (ex: `"gateway"`)

  ## Exemplo

      event = Shared.Event.new("promocao.recebida", %{"nome" => "Clean Code"}, "gateway")
      event.id        #=> "f47ac10b-58cc-4372-a567-0e02b2c3d479"
      event.signature #=> nil
  """
  @spec new(String.t(), map(), String.t()) :: t()
  def new(type, payload, source) do
    %Shared.Event{
      id: generate_uuid(),
      type: type,
      payload: payload,
      source: source,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Assina o evento com a chave privada do microsservico produtor.

  Gera o payload canonico (JSON de todos os campos exceto `signature`),
  assina via `Shared.Crypto.sign/2` e retorna o evento com o campo
  `signature` preenchido.

  ## Exemplo

      signed = Shared.Event.sign(event, private_key)
      signed.signature #=> <<48, 130, ...>> (256 bytes)
  """
  @spec sign(t(), Shared.Crypto.private_key()) :: t()
  def sign(event, private_key) do
    signature = Shared.Crypto.sign(signable_payload(event), private_key)
    %{event | signature: signature}
  end

  @doc """
  Verifica a assinatura digital do evento usando a chave publica do produtor.

  Reconstroi o payload canonico e verifica via `Shared.Crypto.verify/3`.
  Retorna `true` se a assinatura e valida, `false` caso contrario.

  ## Exemplo

      if Shared.Event.verify(event, public_key) do
        # processar evento
      else
        # descartar — assinatura invalida
      end
  """
  @spec verify(t(), Shared.Crypto.public_key()) :: boolean()
  def verify(event, public_key) do
    Shared.Crypto.verify(signable_payload(event), event.signature, public_key)
  end

  @doc """
  Gera o payload canonico do evento para assinatura.

  Retorna uma string JSON deterministica contendo todos os campos
  exceto `signature`. Usado internamente por `sign/2` e `verify/2`.
  """
  @spec signable_payload(t()) :: binary()
  def signable_payload(event) do
    %{
      id: event.id,
      type: event.type,
      payload: event.payload,
      source: event.source,
      timestamp: DateTime.to_iso8601(event.timestamp)
    }
    |> Jason.encode!()
  end

  @doc false
  @spec generate_uuid() :: String.t()
  def generate_uuid do
    <<a::48, _v::4, b::12, _var::2, c::62>> = :crypto.strong_rand_bytes(16)

    <<a::48, 0b0100::4, b::12, 0b10::2, c::62>>
    |> bin_to_hex()
  end

  defp bin_to_hex(<<a::32, b::16, c::16, d::16, e::48>>) do
    [a, b, c, d, e]
    |> Enum.map_join("-", &Base.encode16(&1 |> :binary.encode_unsigned(), case: :lower))
  end
end
