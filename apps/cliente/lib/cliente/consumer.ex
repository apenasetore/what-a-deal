defmodule Cliente.Consumer do
  @moduledoc """
  Consumidor de notificacoes do processo Cliente.

  Recebe mensagens de duas fontes diferentes (com formatos diferentes):

  - **`promocao.<categoria>`** — vindo do MS Notificacao, no formato de
    notificacao JSON (nao assinada): `%{"tipo" => ..., "categoria" => ...,
    "promo" => ..., ...}`. O campo `tipo` distingue `"nova"` de `"hot deal"`.

  - **`promocao.destaque`** — vindo direto do MS Ranking, no formato de
    `Shared.Event` envelope assinado. Recebido apenas se o cliente
    estiver inscrito explicitamente em destaques.

  Mensagens em formatos invalidos sao logadas e ignoradas.

  ## Display

  Cada mensagem recebida e formatada e impressa no terminal via
  `IO.puts/1`. O formato exibe timestamp, categoria, tipo e dados da
  promocao quando disponiveis.
  """

  use GenServer

  require Logger

  alias Shared.Event.Envelope

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    rabbitmq = Keyword.fetch!(opts, :rabbitmq)
    routing_keys = Keyword.fetch!(opts, :routing_keys)

    Logger.info("Cliente inscrito em: #{Enum.join(routing_keys, ", ")}")
    Process.send_after(self(), :subscribe, 500)
    {:ok, %{rabbitmq: rabbitmq}}
  end

  @impl true
  def handle_info(:subscribe, state) do
    Shared.RabbitMQ.subscribe(state.rabbitmq, fn routing_key, payload ->
      handle_message(routing_key, payload)
    end)

    {:noreply, state}
  end

  @doc """
  Processa uma mensagem recebida.

  Dispatcha conforme o `routing_key`:
  - `"promocao.destaque"` → decodifica como Event envelope (formato Ranking)
  - qualquer outro `"promocao.<categoria>"` → decodifica como notificacao JSON (formato Notificacao)
  """
  @spec handle_message(String.t(), binary()) :: :ok
  def handle_message("promocao.destaque", payload) do
    case Envelope.decode(payload) do
      {:ok, event} ->
        display_destaque_event(event)

      {:error, reason} ->
        Logger.warning("Erro ao decodificar promocao.destaque: #{inspect(reason)}")
    end

    :ok
  end

  def handle_message(routing_key, payload) do
    case Jason.decode(payload) do
      {:ok, notif} ->
        display_notificacao(routing_key, notif)

      {:error, reason} ->
        Logger.warning("Erro ao decodificar #{routing_key}: #{inspect(reason)}")
    end

    :ok
  end

  # --- Display ---

  @doc """
  Formata e imprime uma notificacao JSON vinda do MS Notificacao.
  """
  @spec display_notificacao(String.t(), map()) :: :ok
  def display_notificacao(routing_key, notif) do
    timestamp = format_timestamp(notif["timestamp"])
    categoria = notif["categoria"] || extract_categoria(routing_key)
    tipo = notif["tipo"] || "nova"
    promo = notif["promo"] || %{}
    label = if tipo == "hot deal", do: "HOT DEAL", else: "Nova promocao"

    IO.puts("\n[#{timestamp}] [#{categoria}] #{label}: #{format_promo(promo)}")
    :ok
  end

  @doc """
  Formata e imprime um Event envelope vindo do MS Ranking direto na
  routing key `promocao.destaque`.

  Como o Ranking publica a promocao completa no payload (apos a opcao
  (a) da integracao Gateway -> Ranking), reutilizamos o mesmo
  `format_promo/1` da `display_notificacao/2` — ficando consistente.
  """
  @spec display_destaque_event(Shared.Event.t()) :: :ok
  def display_destaque_event(event) do
    timestamp = format_timestamp(DateTime.to_iso8601(event.timestamp))
    categoria = event.payload["categoria"] || "?"

    IO.puts("\n[#{timestamp}] [#{categoria}] HOT DEAL: #{format_promo(event.payload)}")
    :ok
  end

  defp format_promo(promo) when is_map(promo) do
    nome = promo["nome"] || "?"
    loja = promo["loja"]
    original = promo["preco_original"]
    promocional = promo["preco_promocional"]

    base = ~s("#{nome}")
    base = if loja, do: "#{base} — #{loja}", else: base

    if original && promocional do
      "#{base} (R$#{format_price(original)} -> R$#{format_price(promocional)})"
    else
      base
    end
  end

  defp format_promo(_), do: "?"

  defp format_price(price) when is_float(price), do: :erlang.float_to_binary(price, decimals: 2)
  defp format_price(price) when is_integer(price), do: "#{price}.00"
  defp format_price(price), do: "#{price}"

  defp format_timestamp(nil), do: "?"

  defp format_timestamp(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} -> Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
      _ -> iso
    end
  end

  defp extract_categoria("promocao." <> cat), do: cat
  defp extract_categoria(_), do: "?"
end
