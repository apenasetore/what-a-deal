defmodule Mix.Tasks.GenKeys do
  @shortdoc "Gera pares de chaves RSA para os microsservicos que assinam eventos"

  @moduledoc """
  Gera pares de chaves RSA 2048 para os microsservicos que precisam
  assinar eventos: `gateway`, `promocao` e `ranking`.

  As chaves sao salvas em `apps/shared/priv/keys/<servico>/private.pem`
  e `public.pem`.

  ## Uso

      mix gen_keys

  Por padrao, nao sobrescreve chaves existentes. Use `--force` para
  regenerar todas as chaves:

      mix gen_keys --force

  ## Servicos

  - `gateway` — assina `promocao.recebida` e `promocao.voto`
  - `promocao` — assina `promocao.publicada`
  - `ranking` — assina `promocao.destaque`

  O servico `notificacao` nao precisa de chaves porque nao publica
  eventos assinados — apenas republica em routing keys de categoria.
  """

  use Mix.Task

  @services ["gateway", "promocao", "ranking"]
  @source_priv "apps/shared/priv"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [force: :boolean])
    force? = Keyword.get(opts, :force, false)

    Application.ensure_all_started(:shared)

    Enum.each(@services, &generate_for(&1, force?))

    Mix.shell().info("\nChaves salvas em #{@source_priv}/keys/")
    Mix.shell().info("Lembre de rodar `mix compile` para que sejam copiadas para o build.")
  end

  defp generate_for(service, force?) do
    if keys_exist?(service) and not force? do
      Mix.shell().info("[skip] #{service} (chaves ja existem — use --force para regenerar)")
    else
      {priv, pub} = Shared.Crypto.generate_key_pair()
      :ok = save_keys_to_source(service, priv, pub)
      Mix.shell().info("[ok]   #{service}")
    end
  end

  defp save_keys_to_source(service, private_key, public_key) do
    dir = Path.join([@source_priv, "keys", service])
    File.mkdir_p!(dir)

    private_pem =
      :public_key.pem_encode([
        :public_key.pem_entry_encode(:RSAPrivateKey, private_key)
      ])

    public_pem =
      :public_key.pem_encode([
        :public_key.pem_entry_encode(:SubjectPublicKeyInfo, public_key)
      ])

    File.write!(Path.join(dir, "private.pem"), private_pem)
    File.write!(Path.join(dir, "public.pem"), public_pem)
    :ok
  end

  defp keys_exist?(service) do
    dir = Path.join([@source_priv, "keys", service])
    File.exists?(Path.join(dir, "private.pem")) and File.exists?(Path.join(dir, "public.pem"))
  end
end
