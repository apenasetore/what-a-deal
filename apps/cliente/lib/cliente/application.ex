defmodule Cliente.Application do
  @moduledoc """
  Application callback do processo Cliente Consumidor.

  Inicia a supervision tree:

  1. `Shared.RabbitMQ` — wrapper de conexao AMQP, configurado para
     declarar uma fila exclusiva por instancia (`cliente_<rand>`,
     `auto_delete: true`) bindada nas routing keys das categorias de
     interesse + opcionalmente `promocao.destaque`.
  2. `Cliente.Consumer` — registra callback que decodifica e exibe
     notificacoes recebidas no terminal.

  ## Configuracao por instancia

  Para suportar multiplos clientes em terminais diferentes (cada um com
  categorias de interesse distintas), as opcoes podem vir de duas fontes
  com a seguinte precedencia:

  1. **Variaveis de ambiente** (override): `CLIENTE_CATEGORIAS`,
     `CLIENTE_DESTAQUE`, `CLIENTE_AUTOSTART`
  2. **Config do app** (default): `:cliente, :categorias`,
     `:cliente, :destaque`, `:cliente, :autostart`

  ## Rodando varios clientes

  Para evitar que rodar `iex -S mix` em terminais diferentes suba
  duplicata dos outros microsservicos (gateway/promocao/ranking/notificacao),
  cada cliente extra deve ser iniciado a partir do diretorio
  `apps/cliente`, nao do umbrella root:

      # Terminal 1 (backend completo + 1 cliente padrao):
      iex -S mix

      # Terminal 2 (cliente apenas em "jogo", sem destaque):
      cd apps/cliente
      CLIENTE_CATEGORIAS=jogo CLIENTE_DESTAQUE=false iex -S mix

      # Terminal 3 (cliente apenas em "eletronico" + destaque):
      cd apps/cliente
      CLIENTE_CATEGORIAS=eletronico CLIENTE_DESTAQUE=true iex -S mix

  Cada instancia gera nome de fila unico (`cliente_<8 hex>`), entao nao
  ha conflito entre filas. RabbitMQ entrega copias independentes da
  mesma mensagem para cada fila bindada na mesma routing key.

  ## RabbitMQ URL

  Pode ser sobrescrita via `RABBITMQ_URL`. Default:
  `amqp://guest:guest@localhost`.
  """

  use Application

  @rabbitmq_name :cliente_rabbitmq

  @impl true
  def start(_type, _args) do
    if autostart?() do
      categorias = categorias()
      destaque? = destaque?()

      routing_keys = build_routing_keys(categorias, destaque?)
      queue = generate_queue_name()

      children = [
        {Shared.RabbitMQ,
         name: @rabbitmq_name,
         url: rabbitmq_url(),
         queues: [{queue, routing_keys}],
         queue_opts: [auto_delete: true]},
        {Cliente.Consumer, rabbitmq: @rabbitmq_name, routing_keys: routing_keys}
      ]

      opts = [strategy: :rest_for_one, name: Cliente.Supervisor]
      Supervisor.start_link(children, opts)
    else
      Supervisor.start_link([], strategy: :one_for_one, name: Cliente.Supervisor)
    end
  end

  @doc """
  Retorna a lista de categorias de interesse, com env var sobrepondo a config.

  ## Precedencia

  1. `CLIENTE_CATEGORIAS=livro,jogo` (string CSV, espacos sao removidos)
  2. `Application.get_env(:cliente, :categorias, [])`
  """
  @spec categorias() :: [String.t()]
  def categorias do
    case env_or_config("CLIENTE_CATEGORIAS", :categorias, []) do
      csv when is_binary(csv) -> csv |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
      list when is_list(list) -> list
    end
  end

  @doc """
  Retorna se o cliente esta inscrito em `promocao.destaque`, com env var
  sobrepondo a config.

  ## Precedencia

  1. `CLIENTE_DESTAQUE=true` ou `CLIENTE_DESTAQUE=false`
  2. `Application.get_env(:cliente, :destaque, false)`
  """
  @spec destaque?() :: boolean()
  def destaque?, do: to_bool(env_or_config("CLIENTE_DESTAQUE", :destaque, false))

  @doc """
  Retorna se o cliente deve subir automaticamente no startup.

  Em ambiente de teste e quando se quer rodar varios clientes em
  terminais separados (a partir do `apps/cliente`), a config pode estar
  como `false` no umbrella mas o env var pode forcar `true` no terminal
  do cliente.

  ## Precedencia

  1. `CLIENTE_AUTOSTART=true` ou `CLIENTE_AUTOSTART=false`
  2. `Application.get_env(:cliente, :autostart, true)`
  """
  @spec autostart?() :: boolean()
  def autostart?, do: to_bool(env_or_config("CLIENTE_AUTOSTART", :autostart, true))

  defp env_or_config(env_var, config_key, default) do
    case System.get_env(env_var) do
      nil -> Application.get_env(:cliente, config_key, default)
      "" -> Application.get_env(:cliente, config_key, default)
      val -> val
    end
  end

  defp to_bool(val) when is_boolean(val), do: val

  defp to_bool(val) when is_binary(val) do
    String.downcase(val) in ["true", "1", "yes"]
  end

  @doc """
  Constroi a lista de routing keys a partir das categorias e do flag de destaque.

  ## Exemplos

      iex> Cliente.Application.build_routing_keys(["livro", "jogo"], true)
      ["promocao.categoria.livro", "promocao.categoria.jogo", "promocao.categoria.destaque"]

      iex> Cliente.Application.build_routing_keys(["livro"], false)
      ["promocao.categoria.livro"]

      iex> Cliente.Application.build_routing_keys([], true)
      ["promocao.categoria.destaque"]
  """
  @spec build_routing_keys([String.t()], boolean()) :: [String.t()]
  def build_routing_keys(categorias, destaque?) do
    categoria_keys = Enum.map(categorias, &"promocao.categoria.#{&1}")
    if destaque?, do: categoria_keys ++ ["promocao.categoria.destaque"], else: categoria_keys
  end

  @doc """
  Gera um nome de fila unico para esta instancia (`cliente_<8 hex>`).
  """
  @spec generate_queue_name() :: String.t()
  def generate_queue_name do
    suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "cliente_#{suffix}"
  end

  @doc false
  def rabbitmq_name, do: @rabbitmq_name

  @doc false
  def rabbitmq_url do
    System.get_env("RABBITMQ_URL", "amqp://guest:guest@localhost")
  end
end
