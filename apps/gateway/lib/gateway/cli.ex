defmodule Gateway.CLI do
  @moduledoc """
  Interface terminal interativa do Gateway.

  Exibe um menu com opcoes para cadastrar promocoes, listar promocoes
  validadas, votar em promocoes e sair do sistema.
  """

  def start_link(_opts) do
    Task.start_link(fn -> loop() end)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary
    }
  end

  def loop do
    IO.puts("""

    === PromoHub Gateway ===
    1. Cadastrar promocao
    2. Listar promocoes
    3. Votar em promocao
    4. Sair
    """)

    IO.gets("Escolha uma opcao: ")
    |> String.trim()
    |> handle_option()
  end

  defp handle_option("1") do
    cadastrar_promocao()
    loop()
  end

  defp handle_option("2") do
    listar_promocoes()
    loop()
  end

  defp handle_option("3") do
    votar_promocao()
    loop()
  end

  defp handle_option("4") do
    IO.puts("\nAte mais!")
  end

  defp handle_option(_) do
    IO.puts("\nOpcao invalida!")
    loop()
  end

  # --- Cadastrar ---

  defp cadastrar_promocao do
    IO.puts("\n--- Cadastrar Promocao ---")
    nome = prompt("Nome do produto: ")
    descricao = prompt("Descricao: ")
    preco_original = prompt("Preco original (ex: 89.90): ") |> parse_float()
    preco_promocional = prompt("Preco promocional (ex: 45.00): ") |> parse_float()
    categoria = prompt("Categoria (ex: livro, eletronico): ")
    loja = prompt("Loja: ")

    promo_data = %{
      "nome" => nome,
      "descricao" => descricao,
      "preco_original" => preco_original,
      "preco_promocional" => preco_promocional,
      "categoria" => categoria,
      "loja" => loja
    }

    case Gateway.Publisher.publish_promocao(promo_data) do
      :ok -> IO.puts("\nPromocao enviada para validacao!")
      {:error, reason} -> IO.puts("\nErro ao enviar: #{inspect(reason)}")
    end
  end

  # --- Listar ---

  defp listar_promocoes do
    promos = Gateway.PromoStore.list()

    if Enum.empty?(promos) do
      IO.puts("\nNenhuma promocao validada ainda.")
    else
      IO.puts("\n--- Promocoes Validadas ---")

      promos
      |> Enum.with_index(1)
      |> Enum.each(fn {promo, idx} ->
        IO.puts("#{idx}. [#{promo["categoria"]}] #{promo["nome"]} — #{promo["loja"]}")

        IO.puts(
          "   R$#{format_price(promo["preco_original"])} -> R$#{format_price(promo["preco_promocional"])}"
        )

        IO.puts("   #{promo["descricao"]}\n")
      end)
    end
  end

  # --- Votar ---

  defp votar_promocao do
    promos = Gateway.PromoStore.list()

    if Enum.empty?(promos) do
      IO.puts("\nNenhuma promocao disponivel para votar.")
    else
      IO.puts("\n--- Votar em Promocao ---")

      promos
      |> Enum.with_index(1)
      |> Enum.each(fn {promo, idx} ->
        IO.puts("#{idx}. #{promo["nome"]} — #{promo["loja"]}")
      end)

      escolha = prompt("\nNumero da promocao: ") |> parse_int()

      promos
      |> Enum.at(escolha - 1)
      |> registrar_voto()
    end
  end

  defp registrar_voto(nil), do: IO.puts("Opcao invalida!")

  defp registrar_voto(promo) do
    voto = prompt("Voto (+1 ou -1): ") |> parse_int()

    if voto in [1, -1] do
      case Gateway.Publisher.publish_voto(promo["id"], voto) do
        :ok -> IO.puts("\nVoto registrado!")
        {:error, reason} -> IO.puts("\nErro ao votar: #{inspect(reason)}")
      end
    else
      IO.puts("Voto invalido! Use +1 ou -1.")
    end
  end

  # --- Helpers ---

  defp prompt(message) do
    IO.gets(message) |> String.trim()
  end

  defp parse_float(str) do
    case Float.parse(str) do
      {val, _} -> val
      :error -> 0.0
    end
  end

  defp parse_int(str) do
    case Integer.parse(str) do
      {val, _} -> val
      :error -> 0
    end
  end

  defp format_price(price) when is_float(price), do: :erlang.float_to_binary(price, decimals: 2)
  defp format_price(price) when is_integer(price), do: "#{price}.00"
  defp format_price(price), do: "#{price}"
end
