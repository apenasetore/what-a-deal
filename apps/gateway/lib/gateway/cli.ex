defmodule Gateway.CLI do
  @moduledoc """
  Interface terminal interativa do Gateway.

  Exibe um menu com opcoes para cadastrar promocoes, listar promocoes
  validadas, votar em promocoes e sair do sistema.
  """

  def loop do
    IO.puts("""

    === What-a-Deal Gateway ===
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

    with {:ok, preco_original} <- prompt_float("Preco original (ex: 89.90): "),
         {:ok, preco_promocional} <- prompt_float("Preco promocional (ex: 45.00): ") do
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
    else
      :error -> IO.puts("\nValor numerico invalido. Cadastro cancelado.")
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

      case prompt_int("\nNumero da promocao: ") do
        {:ok, escolha} when escolha >= 1 and escolha <= length(promos) ->
          promos |> Enum.at(escolha - 1) |> registrar_voto()

        _ ->
          IO.puts("Opcao invalida!")
      end
    end
  end

  defp registrar_voto(promo) do
    case prompt_int("Voto (+1 ou -1): ") do
      {:ok, voto} when voto in [1, -1] ->
        case Gateway.Publisher.publish_voto(promo, voto) do
          :ok -> IO.puts("\nVoto registrado!")
          {:error, reason} -> IO.puts("\nErro ao votar: #{inspect(reason)}")
        end

      _ ->
        IO.puts("Voto invalido! Use +1 ou -1.")
    end
  end

  # --- Helpers ---

  defp prompt(message) do
    IO.gets(message) |> String.trim()
  end

  defp prompt_float(message) do
    case Float.parse(prompt(message)) do
      {val, _} -> {:ok, val}
      :error -> :error
    end
  end

  defp prompt_int(message) do
    case Integer.parse(prompt(message)) do
      {val, _} -> {:ok, val}
      :error -> :error
    end
  end

  defp format_price(price) when is_float(price), do: :erlang.float_to_binary(price, decimals: 2)
  defp format_price(price) when is_integer(price), do: "#{price}.00"
  defp format_price(price), do: "#{price}"
end
