defmodule Mix.Tasks.Taina.Senha do
  @shortdoc "Define uma nova senha para uma pessoa da comunidade (recuperacao do operador)"

  @moduledoc """
  Recuperacao de operador: define uma senha nova para a pessoa `<usuario>` sem
  depender de a interface responder. E o caminho de volta do cenario pior, o
  unico zelador que esqueceu a propria senha (a revisao 0.1.0, achado C1).

  A senha nova vem por `--password` (scriptado) ou por pergunta no terminal
  (entrada escondida, pedida duas vezes para conferir). O usuario aceita so o
  nome (`maria`) ou o handle inteiro (`maria@tekoa.example.org`).

      mix taina.senha maria
      mix taina.senha maria --password nova-senha-123

  Um link de redefinicao pendente, se havia, e queimado junto. A troca NAO
  entra no mural: nenhuma pessoa logada fez o ato, o ato foi no shell. Se a
  conta estiver desativada, a senha muda mesmo assim e a tarefa avisa que o
  login continua bloqueado ate alguem reativar em Moradores.

  Nao sobe a app inteira (endpoint e fila nao sao precisos aqui): so o Repo.
  """

  use Mix.Task

  alias Taina.Maraca
  alias Taina.Repo
  alias Ypy.Maraca.Ava

  @requirements ["app.config"]

  @impl Mix.Task
  def run(args) do
    {opts, args, _invalid} = OptionParser.parse(args, strict: [password: :string])

    case args do
      [username] ->
        run(username, Keyword.get(opts, :password))

      _ ->
        Mix.raise("usage: mix taina.senha <usuario> [--password <nova-senha>]")
    end
  end

  defp run(username, password_opt) do
    # A app inteira nao sobe aqui (endpoint e fila nao sao precisos): so o
    # Repo. `app.config` carrega config mas nao aplica aplicacoes, entao o
    # driver do banco sobe antes do Repo (o Registry do Ecto vem com ele).
    {:ok, _} = Application.ensure_all_started(:ecto_sqlite3)

    if is_nil(Process.whereis(Repo)) do
      {:ok, _} = Repo.start_link()
    end

    case Maraca.get_tekoa() do
      {:ok, tekoa} ->
        username = normalize_username(username)

        case find_ava(tekoa, username) do
          nil ->
            Mix.shell().error(~s(Nao encontrei "#{username}" nesta comunidade. Confira o nome em Moradores.))
            exit({:shutdown, 1})

          %Ava{} = ava ->
            warn_if_deactivated(ava)
            set_password(tekoa, ava, password_opt)
        end

      {:error, :not_bootstrapped} ->
        Mix.shell().error("Esta caixa ainda nao tem comunidade criada (rode a inicializacao primeiro).")
        exit({:shutdown, 1})
    end
  end

  # O usuario pode vir so o nome (`maria`) ou o handle inteiro
  # (`maria@tekoa.example.org`): o banco guarda so o nome, entao fica com a
  # parte de antes do @, apos a normalizacao (trim e minusculas).
  defp normalize_username(input) do
    input
    |> Ypy.Handle.normalize()
    |> String.split("@", parts: 2)
    |> List.first()
  end

  # `with_tekoa/2` abre transacao e cobra {:ok, _}/{:error, _} do callback:
  # o "nao achou" (nil) sobe como {:ok, nil} e o run/2 decide o que mostrar.
  defp find_ava(%{id: tekoa_id, public_id: public_id}, username) do
    {:ok, ava} =
      Repo.with_tekoa(public_id, fn ->
        {:ok, Repo.get_by(Ava, username: username, tekoa_id: tekoa_id)}
      end)

    ava
  end

  defp set_password(tekoa, ava, password_opt) do
    password = password_opt || ask_password()

    case Repo.with_tekoa(tekoa.public_id, fn ->
           Repo.update(Ava.reset_changeset(ava, %{password: password}))
         end) do
      {:ok, _ava} ->
        Mix.shell().info([
          :green,
          "Senha de #{display_name(ava)} definida. Um link de redefinicao pendente, se havia, foi queimado.",
          :reset
        ])

      {:error, %Ecto.Changeset{}} ->
        Mix.shell().error("A senha nova precisa ter pelo menos 8 caracteres.")
        exit({:shutdown, 1})
    end
  end

  defp ask_password do
    password = ask("Nova senha (minimo 8 caracteres): ")
    confirm = ask("Confirme a senha nova: ")

    cond do
      password == "" ->
        Mix.shell().error("A senha nao pode ser vazia. Tente de novo.")
        exit({:shutdown, 1})

      password != confirm ->
        Mix.shell().error("As duas senhas nao sao iguais. Tente de novo.")
        exit({:shutdown, 1})

      true ->
        password
    end
  end

  # A entrada escondida e do terminal (:io.get_password, OTP 28). Sem terminal
  # de verdade (entrada em pipe), o protocolo de senha nao existe: qualquer
  # saida que nao seja a senha cai para a pergunta normal do Mix, que le de
  # qualquer entrada (a senha aparece na tela, no pior caso).
  defp ask(message) do
    password =
      if function_exported?(:io, :get_password, 1) do
        case :io.get_password(message) do
          {:ok, password} -> password
          {:error, _reason} -> Mix.shell().prompt(message)
        end
      else
        Mix.shell().prompt(message)
      end

    password |> IO.iodata_to_binary() |> String.replace_suffix("\n", "")
  rescue
    _ -> message |> Mix.shell().prompt() |> String.replace_suffix("\n", "")
  end

  defp warn_if_deactivated(%Ava{deactivated_at: at}) when not is_nil(at) do
    Mix.shell().info([
      :yellow,
      "Atencao: esta conta esta desativada. Mesmo com a senha nova, o login continua bloqueado ate alguem reativar em Moradores.",
      :reset
    ])
  end

  defp warn_if_deactivated(%Ava{}), do: :ok

  defp display_name(%Ava{display_name: nil} = ava), do: ava.username
  defp display_name(%Ava{display_name: name}), do: name
end
