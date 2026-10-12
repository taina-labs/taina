defmodule TainaWeb.SetupLive do
  @moduledoc """
  Wizard de primeiro boot (3 passos): nome da comunidade, conta de quem cuida
  (zelador) e armazenamento. Cada passo vive na própria URL (`?passo=`): o
  gesto de voltar do Android desce um passo em vez de sair do wizard. A
  validação roda ao vivo e espelha as regras do servidor (`Tekoa`/`Ava`) para
  o erro ficar no campo, não virar falha de changeset no POST que derruba o
  wizard inteiro; o submit final valida todos os passos (somente leitura) e só
  então solta o POST tradicional para `SetupController` (`phx-trigger-action`),
  que faz `Maraca.bootstrap/2` e abre a sessão na mesma requisição.

  Deriva da RFC 002 (D2): só roda em instância virgem, se já existe Tekoa,
  redireciona para o login. A conta criada é a do zelador (quem cuida da
  máquina); identidade por nome de usuário, sem e-mail (RFC_003, seção 4).
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
       |> assign(
         :data,
         %{
           "community_name" => "",
           "username" => "",
           "display_name" => "",
           "password" => "",
           "password_confirmation" => ""
         }
       )
       |> assign(:errors, %{})
       |> assign(:trigger_submit, false)
       |> assign(:free_space, free_space())}
    end
  end

  # ?passo= na URL: cada passo empurra a própria URL, então o gesto de voltar
  # do Android desce um passo em vez de sair do wizard (e um refresh ou retorno
  # ao wizard cai no passo certo). Só aceita 1..3; sem ?passo= (voltou do passo
  # 2), cai no passo 1.
  @impl true
  def handle_params(%{"passo" => passo}, _uri, %{assigns: %{step: current}} = socket) do
    {:noreply, assign(socket, :step, step_from_passo(passo, current))}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, assign(socket, :step, 1)}

  @impl true
  def handle_event("validate", %{"setup" => params}, socket) do
    data = normalize_data(Map.merge(socket.assigns.data, params))
    {:noreply, socket |> assign(:data, data) |> assign(:errors, Map.drop(socket.assigns.errors, Map.keys(params)))}
  end

  def handle_event("next", %{"setup" => params}, socket) do
    data = normalize_data(Map.merge(socket.assigns.data, params))

    case validate_step(socket.assigns.step, data) do
      %{} = errors when map_size(errors) == 0 ->
        next_step = min(socket.assigns.step + 1, 3)

        {:noreply,
         socket
         |> assign(:data, data)
         |> assign(:errors, %{})
         |> push_patch(to: ~p"/setup?passo=#{next_step}")}

      errors ->
        {:noreply, socket |> assign(:data, data) |> assign(:errors, errors)}
    end
  end

  # Validação somente leitura de todos os passos antes de soltar o POST para o
  # SetupController: erro de formulário volta para o passo do problema em vez
  # de virar falha de changeset no servidor.
  def handle_event("final", %{"setup" => params}, socket) do
    data = normalize_data(Map.merge(socket.assigns.data, params))

    case validate_all_steps(data) do
      %{} = errors when map_size(errors) == 0 ->
        {:noreply, assign(socket, :trigger_submit, true)}

      errors ->
        {:noreply,
         socket
         |> assign(:data, data)
         |> assign(:errors, errors)
         |> push_patch(to: ~p"/setup?passo=#{error_step(errors)}")}
    end
  end

  def handle_event("final", _params, socket), do: {:noreply, socket}

  # O passo vive na URL: o patch coloca o passo anterior no histórico e o
  # `handle_params` aplica.
  def handle_event("back", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/setup?passo=#{max(socket.assigns.step - 1, 1)}")}
  end

  defp step_from_passo(passo, current) when is_binary(passo) do
    case Integer.parse(passo) do
      {step, ""} when step in 1..3 -> step
      _other -> current
    end
  end

  defp step_from_passo(_passo, current), do: current

  # O username é chave de acesso (e semente do handle federado): normaliza no
  # cliente como o servidor normaliza (`Ava.normalize_username/1`), antes de
  # validar. "João" ou "ana clara" falham no campo, não no POST.
  @username_format ~r/^[a-z0-9._-]+$/

  defp normalize_data(data) do
    case data["username"] do
      nil -> data
      username -> Map.put(data, "username", username |> String.trim() |> String.downcase())
    end
  end

  defp validate_step(1, data) do
    %{}
    |> validate_presence(data, "community_name", gettext("dê um nome à comunidade"))
    |> validate_length_in(data, "community_name", 3..100, gettext("de 3 a 100 caracteres"))
  end

  defp validate_step(2, data) do
    %{}
    |> validate_username(data)
    |> validate_length_in(data, "display_name", 0..80, gettext("de no máximo 80 caracteres"))
    |> validate_password(data)
    |> validate_confirmation(data)
  end

  defp validate_step(_step, _data), do: %{}

  # Espelha `Ava.validate_username/1` (3 a 50 caracteres, só minúsculas,
  # números, ponto, hífen e _): o erro de formato aparece no campo aqui.
  defp validate_username(errors, data) do
    username = data["username"] || ""

    cond do
      username == "" ->
        Map.put(errors, "username", gettext("escolha um nome de usuário"))

      String.length(username) not in 3..50 ->
        Map.put(errors, "username", gettext("de 3 a 50 caracteres"))

      not Regex.match?(@username_format, username) ->
        Map.put(errors, "username", gettext("Use só letras minúsculas, números, ponto, hífen ou _, sem espaços."))

      true ->
        errors
    end
  end

  # Espelha os `validate_length` do servidor (`Tekoa`: nome 3 a 100; `Ava`:
  # display_name até 80). Vazio não acusa aqui: presença (ou opcionalidade)
  # cuida disso.
  defp validate_length_in(errors, data, key, range, message) do
    value = data[key] || ""

    if String.trim(value) != "" and String.length(value) not in range,
      do: Map.put(errors, key, message),
      else: errors
  end

  defp validate_all_steps(data) do
    1
    |> validate_step(data)
    |> Map.merge(validate_step(2, data))
    |> Map.merge(validate_step(3, data))
  end

  # Primeiro passo que tem problema: para onde a validação final manda de volta.
  defp error_step(errors) do
    cond do
      Map.has_key?(errors, "community_name") ->
        1

      Map.has_key?(errors, "username") or Map.has_key?(errors, "display_name") or
        Map.has_key?(errors, "password") or Map.has_key?(errors, "password_confirmation") ->
        2

      true ->
        3
    end
  end

  defp validate_presence(errors, data, key, message) do
    if String.trim(data[key] || "") == "", do: Map.put(errors, key, message), else: errors
  end

  defp validate_password(errors, data) do
    if String.length(data["password"] || "") < 8,
      do: Map.put(errors, "password", gettext("a senha precisa de pelo menos 8 caracteres")),
      else: errors
  end

  defp validate_confirmation(errors, data) do
    if data["password_confirmation"] == data["password"],
      do: errors,
      else: Map.put(errors, "password_confirmation", gettext("as duas senhas não são iguais"))
  end

  # Espaço livre no volume do storage, melhor esforço (`df` POSIX). Falhou?
  # O número simplesmente não aparece: é conforto, não requisito.
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
        <div class="col gap-4 text-center mt-10 mb-8 items-center">
          <.icon name="spark" size={48} class="spark" />
          <h1 id="step-heading-1" tabindex="-1" phx-mounted={JS.focus()} class="type-display">Tainá</h1>
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
          <.button type="submit" variant="primary" class="w-full" phx-disable-with={gettext("Começar...")}>
            {gettext("Começar")}
          </.button>
        </form>
      </div>

      <div :if={@step == 2} class="col flex-1">
        <.icon_button name="chevron-left" label={gettext("Voltar")} phx-click="back" />
        <div class="col gap-3 mt-4 mb-6">
          <h1 id="step-heading-2" tabindex="-1" phx-mounted={JS.focus()} class="type-h1">
            {gettext("Crie a conta de quem cuida")}
          </h1>
          <p class="type-body text-secondary">
            {gettext("Você é o primeiro zelador desta comunidade. Guarde bem este acesso: quem o tem cuida da máquina.")}
          </p>
          <.steps current={2} />
          <p class="type-label text-faint">{gettext("Passo 2 de 3: quem cuida")}</p>
        </div>

        <form id="setup-step-2" phx-change="validate" phx-submit="next" class="col gap-5 flex-1">
          <.input
            label={gettext("Seu nome de usuário")}
            name="setup[username]"
            id="setup_username"
            value={@data["username"]}
            placeholder={gettext("ex.: ana")}
            help={gettext("Sem espaços. É com ele que você entra.")}
            autocomplete="username"
            autocapitalize="none"
            spellcheck="false"
            autocorrect="off"
            errors={List.wrap(@errors["username"])}
          />
          <.input
            label={gettext("Nome de exibição (opcional)")}
            name="setup[display_name]"
            id="setup_display_name"
            value={@data["display_name"]}
            placeholder={gettext("ex.: Ana Oliveira")}
            help={gettext("Como seu nome aparece para a comunidade.")}
          />
          <.input
            label={gettext("Senha")}
            type="password"
            name="setup[password]"
            id="setup_password"
            value={@data["password"]}
            placeholder={gettext("mínimo 8 caracteres")}
            help={gettext("Pelo menos 8 caracteres. Uma frase que só você lembra é ainda melhor.")}
            autocomplete="new-password"
            errors={List.wrap(@errors["password"])}
          >
            <:trailing><.password_toggle target="setup_password" /></:trailing>
          </.input>
          <.input
            label={gettext("Confirme a senha")}
            type="password"
            name="setup[password_confirmation]"
            id="setup_password_confirmation"
            value={@data["password_confirmation"]}
            placeholder={gettext("a mesma senha")}
            autocomplete="new-password"
            errors={List.wrap(@errors["password_confirmation"])}
          >
            <:trailing><.password_toggle target="setup_password_confirmation" /></:trailing>
          </.input>
          <div class="flex-1"></div>
          <.button type="submit" variant="primary" class="w-full" phx-disable-with={gettext("Continuar...")}>
            {gettext("Continuar")}
          </.button>
        </form>
      </div>

      <div :if={@step == 3} class="col flex-1">
        <.icon_button name="chevron-left" label={gettext("Voltar")} phx-click="back" />
        <div class="col gap-3 mt-4 mb-6">
          <h1 id="step-heading-3" tabindex="-1" phx-mounted={JS.focus()} class="type-h1">
            {gettext("O disco da comunidade")}
          </h1>
          <p class="type-body text-secondary">
            {gettext("Este é o disco da comunidade. Ele é escolhido na instalação da caixa e não pode ser trocado por aqui.")}
          </p>
          <.steps current={3} />
          <p class="type-label text-faint">{gettext("Passo 3 de 3: armazenamento")}</p>
        </div>

        <div class="col gap-4 flex-1">
          <.card class="row gap-3 items-center">
            <.icon name="check" size={22} class="text-success" />
            <div class="flex-1">
              <p class="type-label">
                {gettext("Disco interno")}{if @free_space, do: ", #{format_bytes(@free_space)} #{gettext("livres")}"}
              </p>
            </div>
          </.card>

          <.card class="row gap-3 items-center">
            <.icon name="download" size={22} class="text-muted" />
            <div class="flex-1">
              <p class="type-label">{gettext("Disco USB externo")}</p>
              <p class="type-body-sm text-muted">{gettext("Disco externo se prepara na instalação, não por aqui.")}</p>
            </div>
          </.card>

          <.card class="mt-2">
            <p class="type-overline text-faint mb-2">{gettext("Resumo")}</p>
            <p class="type-body">
              {@data["community_name"]}, {gettext("zelador(a)")} {@data["username"]}, {gettext("disco interno")}
            </p>
          </.card>

          <div class="flex-1"></div>

          <form id="setup-submit" phx-submit="final" phx-trigger-action={@trigger_submit} action={~p"/setup"} method="post" class="col">
            <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
            <input type="hidden" name="setup[community_name]" value={@data["community_name"]} />
            <input type="hidden" name="setup[username]" value={@data["username"]} />
            <input type="hidden" name="setup[display_name]" value={@data["display_name"]} />
            <input type="hidden" name="setup[password]" value={@data["password"]} />
            <input type="hidden" name="setup[password_confirmation]" value={@data["password_confirmation"]} />
            <.button type="submit" variant="primary" class="w-full" phx-disable-with={gettext("Criar minha nuvem...")}>
              {gettext("Criar minha nuvem")}
            </.button>
          </form>
        </div>
      </div>
    </Layouts.auth>
    """
  end
end
