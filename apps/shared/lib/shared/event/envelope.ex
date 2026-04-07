defmodule Shared.Event.Envelope do
  @moduledoc """
  Serializacao e deserializacao de eventos para JSON.

  Converte entre `Shared.Event.t()` e strings JSON para trafegar no RabbitMQ.
  O campo `signature` (binario) e codificado em Base64 no JSON, pois JSON
  nao suporta dados binarios.

  ## Formato JSON

      {
        "id": "f47ac10b-...",
        "type": "promocao.recebida",
        "payload": {"nome": "Clean Code", "preco": 45.0},
        "source": "gateway",
        "signature": "MIIBI0BAQEFAAOCAQ8A...",
        "timestamp": "2026-04-06T14:30:00.000000Z"
      }

  ## Exemplo

      # Encode
      {:ok, json} = Shared.Event.Envelope.encode(signed_event)

      # Decode
      {:ok, event} = Shared.Event.Envelope.decode(json)
  """

  alias Shared.Event

  @doc """
  Serializa um evento para JSON.

  A `signature` e convertida para Base64 e o `timestamp` para ISO 8601.
  Retorna `{:ok, json_string}` ou `{:error, reason}`.

  ## Exemplo

      {:ok, json} = Shared.Event.Envelope.encode(event)
  """
  @spec encode(Event.t()) :: {:ok, String.t()} | {:error, term()}
  def encode(event) do
    %{
      id: event.id,
      type: event.type,
      payload: event.payload,
      source: event.source,
      signature: Base.encode64(event.signature),
      timestamp: DateTime.to_iso8601(event.timestamp)
    }
    |> Jason.encode()
  end

  @doc """
  Deserializa uma string JSON para um evento.

  Decodifica a `signature` de Base64 e o `timestamp` de ISO 8601.
  Retorna `{:ok, event}` ou `{:error, reason}`.

  ## Exemplo

      {:ok, event} = Shared.Event.Envelope.decode(json)
  """
  @spec decode(String.t()) :: {:ok, Event.t()} | {:error, term()}
  def decode(json_string) do
    with {:ok, map} <- Jason.decode(json_string),
         {:ok, signature} <- Base.decode64(map["signature"]),
         {:ok, timestamp, _} <- DateTime.from_iso8601(map["timestamp"]) do
      event = %Shared.Event{
        id: map["id"],
        type: map["type"],
        payload: map["payload"],
        source: map["source"],
        signature: signature,
        timestamp: timestamp
      }

      {:ok, event}
    else
      :error -> {:error, :invalid_signature}
      {:error, reason} -> {:error, reason}
    end
  end
end
