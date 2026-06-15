defmodule TainaWeb.SetupLive do
  @moduledoc """
  Wizard de primeiro boot (3 passos): nome da comunidade, conta de
  administração e armazenamento. Os passos vivem aqui (validação ao vivo);
  o submit final é um POST tradicional para `SetupController`, que faz
  `Maraca.bootstrap/2` e abre a sessão na mesma requisição.

  Deriva da RFC 002 (D2): só roda em instância virgem, se já existe Tekoa,
  redireciona para o login.

  Nota de drift (design vs. backend): o Penpot marca o e-mail do admin como
  opcional, mas `Ava.changeset/2` exige e-mail; o campo aqui é obrigatório
  até o Maraca suportar contas sem e-mail.
  """

  use TainaWeb, :live_view

  alias Taina.Maraca
  alias TainaWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    if Maraca.bootstrapped?() do
      {:ok, Phoenix.LiveView.redirect(socket, to: ~p"/login")}
    else
      {:ok,
       socket
       |> assign(:page_title, gettext("Primeiros passos"))
       |> assign(:step, 1)
       |> assign(:data, %{"community_name" => "", "username" => "", "email" => "", "password" => ""})
       |> assign(:errors, %{})
       |> assign(:storage_root, Application.fetch_env!(:taina, :storage_root))
       |> assign(:free_space, free_space())}
    end
  end

  @impl true
  def handle_event("validate", %{"setup" => params}, socket) do
    data = Map.merge(socket.assigns.data, params)
    {:noreply, socket |> assign(:data, data) |> assign(:errors, Map.drop(socket.assigns.errors, Map.keys(params)))}
  end

  def handle_event("next", %{"setup" => params}, socket) do
    data = Map.merge(socket.assigns.data, params)

    case validate_step(socket.assigns.step, data) do
      %{} = errors when map_size(errors) == 0 ->
        {:noreply, socket |> assign(:data, data) |> assign(:errors, %{}) |> assign(:step, socket.assigns.step + 1)}

      errors ->
        {:noreply, socket |> assign(:data, data) |> assign(:errors, errors)}
    end
  end

  def handle_event("back", _params, socket) do
    {:noreply, assign(socket, :step, max(socket.assigns.step - 1, 1))}
  end

  defp validate_step(1, data) do
    if String.trim(data["community_name"]) == "",
      do: %{"community_name" => gettext("dê um nome à comunidade")},
      else: %{}
  end

  defp validate_step(2, data) do
    %{}
    |> validate_presence(data, "username", gettext("como devemos te chamar?"))
    |> validate_email(data)
    |> validate_password(data)
  end

  defp validate_presence(errors, data, key, message) do
    if String.trim(data[key] || "") == "", do: Map.put(errors, key, message), else: errors
  end

  defp validate_email(errors, data) do
    if String.match?(data["email"] || "", ~r/^[^\s]+@[^\s]+\.[^\s]+$/),
      do: errors,
      else: Map.put(errors, "email", gettext("informe um e-mail válido"))
  end

  defp validate_password(errors, data) do
    if String.length(data["password"] || "") < 8,
      do: Map.put(errors, "password", gettext("a senha precisa de pelo menos 8 caracteres")),
      else: errors
  end

  # Espaço livre no volume do storage, melhor esforço (`df` POSIX). Falhou?
  # Mostramos só o caminho: o número é conforto, não requisito.
  defp free_space do
    storage_root = Application.fetch_env!(:taina, :storage_root)

    with {out, 0} <- System.cmd("df", ["-k", storage_root], stderr_to_stdout: true),
         [_header, line | _rest] <- String.split(out, "\n"),
         [_fs, _blocks, _used, avail | _] <- String.split(line, ~r/\s+/, trim: true),
         {kbytes, ""} <- Integer.parse(avail) do
      kbytes * 1024
    else
      _ -> nil
    end
  rescue
    _e in ErlangError -> nil
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <div :if={@step == 1} class="col flex-1">
        <div class="col gap-4 text-center mt-10 mb-8" style="align-items: center;">
          <.icon name="spark" size={48} class="spark" />
          <h1 class="type-display">Tainá</h1>
          <p class="type-body text-secondary">
            {gettext("A estrela da manhã da sua comunidade. Arquivos e fotos, na sua casa, sob seu controle.")}
          </p>
          <.steps current={1} />
          <p class="type-label text-faint">{gettext("Passo 1 de 3: sua comunidade")}</p>
        </div>

        <form id="setup-step-1" phx-change="validate" phx-submit="next" class="col gap-6 flex-1">
          <.input
            label={gettext("Nome da comunidade")}
            name="setup[community_name]"
            id="setup_community_name"
            value={@data["community_name"]}
            placeholder={gettext("ex.: Quilombo do Café")}
            help={gettext("Esse nome aparece para todas as pessoas convidadas.")}
            errors={List.wrap(@errors["community_name"])}
            autofocus
          />
          <div class="flex-1"></div>
          <.button type="submit" variant="primary" class="w-full">{gettext("Começar")}</.button>
        </form>
      </div>

      <div :if={@step == 2} class="col flex-1">
        <.icon_button name="chevron-left" label={gettext("Voltar")} phx-click="back" />
        <div class="col gap-3 mt-4 mb-6">
          <h1 class="type-h1">{gettext("Crie a conta de administração")}</h1>
          <p class="type-body text-secondary">
            {gettext("Você é quem cuida desta comunidade. Guarde bem este acesso. Ele controla tudo.")}
          </p>
          <.steps current={2} />
          <p class="type-overline text-faint">{gettext("Passo 2 de 3: administração")}</p>
        </div>

        <form id="setup-step-2" phx-change="validate" phx-submit="next" class="col gap-5 flex-1">
          <.input
            label={gettext("Seu nome")}
            name="setup[username]"
            id="setup_username"
            value={@data["username"]}
            placeholder={gettext("ex.: Ana Oliveira")}
            errors={List.wrap(@errors["username"])}
          />
          <.input
            label={gettext("E-mail")}
            type="email"
            name="setup[email]"
            id="setup_email"
            value={@data["email"]}
            placeholder="voce@exemplo.org"
            help={gettext("Usado só para entrar e recuperar a conta. Nada sai daqui.")}
            errors={List.wrap(@errors["email"])}
          />
          <.input
            label={gettext("Senha")}
            type="password"
            name="setup[password]"
            id="setup_password"
            value={@data["password"]}
            placeholder={gettext("mínimo 8 caracteres")}
            icon="shield"
            help={gettext("Use uma frase longa que só você lembra.")}
            errors={List.wrap(@errors["password"])}
          />
          <div class="flex-1"></div>
          <.button type="submit" variant="primary" class="w-full">{gettext("Continuar")}</.button>
        </form>
      </div>

      <div :if={@step == 3} class="col flex-1">
        <.icon_button name="chevron-left" label={gettext("Voltar")} phx-click="back" />
        <div class="col gap-3 mt-4 mb-6">
          <h1 class="type-h1">{gettext("Onde guardar os arquivos")}</h1>
          <p class="type-body text-secondary">
            {gettext("Escolha o disco onde a comunidade vai morar. Dá pra mudar depois nas configurações.")}
          </p>
          <.steps current={3} />
          <p class="type-overline text-faint">{gettext("Passo 3 de 3: armazenamento")}</p>
        </div>

        <div class="col gap-4 flex-1">
          <div class="radio-card radio-card--selected">
            <.icon name="shield" size={22} class="text-success" />
            <div class="flex-1">
              <p class="type-label">
                {gettext("Disco interno")}{if @free_space, do: ", #{format_bytes(@free_space)} #{gettext("livres")}"}
              </p>
              <p class="type-body-sm text-muted">{@storage_root} ({gettext("recomendado")})</p>
            </div>
            <span class="radio-card__ring"></span>
          </div>

          <div class="radio-card" aria-disabled="true">
            <.icon name="download" size={22} class="text-muted" />
            <div class="flex-1">
              <p class="type-label">{gettext("Disco USB externo")}</p>
              <p class="type-body-sm text-muted">{gettext("Em breve. Conecte e monte o dispositivo")}</p>
            </div>
            <span class="radio-card__ring"></span>
          </div>

          <.card class="mt-2">
            <p class="type-overline text-faint mb-2">{gettext("Resumo")}</p>
            <p class="type-body">
              {@data["community_name"]}, {gettext("admin")} {@data["username"]}, {gettext("disco interno")}
            </p>
          </.card>

          <div class="flex-1"></div>

          <form id="setup-submit" action={~p"/setup"} method="post" class="col">
            <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
            <input type="hidden" name="setup[community_name]" value={@data["community_name"]} />
            <input type="hidden" name="setup[username]" value={@data["username"]} />
            <input type="hidden" name="setup[email]" value={@data["email"]} />
            <input type="hidden" name="setup[password]" value={@data["password"]} />
            <input type="hidden" name="setup[password_confirmation]" value={@data["password"]} />
            <.button type="submit" variant="service" class="w-full">{gettext("Criar minha nuvem")}</.button>
          </form>
        </div>
      </div>
    </Layouts.auth>
    """
  end
end
