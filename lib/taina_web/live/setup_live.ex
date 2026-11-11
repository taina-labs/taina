defmodule TainaWeb.SetupLive do
  @moduledoc """
  Wizard de primeiro boot (3 passos, spec 6.5): boas-vindas
  (cc1037dc-e8ab-80cc-8008-d5e12cb51f5d), conta de quem cuida
  (cc1037dc-e8ab-80cc-8008-d5e12f7715cd) e armazenamento
  (cc1037dc-e8ab-80cc-8008-d5e1336e1a44). Cada passo vive na própria URL
  (`?passo=`): o gesto de voltar do Android desce um passo em vez de sair do
  wizard. A validação roda ao vivo e espelha as regras do servidor
  (`Tekoa`/`Ava`) para o erro ficar no campo, não virar falha de changeset no
  POST que derruba o wizard inteiro; o submit final valida todos os passos
  (somente leitura) e só então solta o POST tradicional para
  `SetupController` (`phx-trigger-action`), que faz `Maraca.bootstrap/2` e
  abre a sessão na mesma requisição.

  O disco é escolhido na instalação da caixa e não pode ser trocado por aqui
  (spec 10): o passo 3 mostra o disco como fato de leitura e decide só o
  LIMITE ("O disco inteiro" / "Um limite" em GB), que o controller valida
  contra o tamanho do disco. Deriva da RFC 002 (D2): só roda em instância
  virgem, se já existe Tekoa, redireciona para o login. A conta criada é a do
  zelador (quem cuida da máquina); identidade por nome de usuário, sem e-mail
  (RFC_003, seção 4).
  """

  use TainaWeb, :live_view

  alias Taina.Maraca
  alias TainaWeb.Disk
  alias TainaWeb.Layouts

  @gigabyte 1024 * 1024 * 1024
  @username_key "username"

  @impl true
  def mount(_params, _session, socket) do
    if Maraca.bootstrapped?() do
      {:ok, Phoenix.LiveView.redirect(socket, to: ~p"/login")}
    else
      {:ok,
       socket
       |> assign(
         :data,
         %{
           "community_name" => "",
           @username_key => "",
           "display_name" => "",
           "password" => "",
           # O board traz "O disco inteiro (recomendado)" já escolhido.
           "storage_quota" => "inteiro",
           "quota_gb" => ""
         }
       )
       |> assign(:disk_size_bytes, Disk.total_bytes())
       |> assign(:errors, %{})
       |> assign(:free_space, free_space())
       |> assign(:page_title, gettext("Primeiros passos"))
       |> assign(:step, 1)
       |> assign(:trigger_submit, false)}
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
    data = maybe_normalize_data(Map.merge(socket.assigns.data, params))

    errors =
      if socket.assigns.step == 3 and Enum.any?(Map.keys(params), &(&1 in ["storage_quota", "quota_gb"])) do
        validate_step(3, data, socket.assigns.disk_size_bytes)
      else
        Map.drop(socket.assigns.errors, Map.keys(params))
      end

    {:noreply, socket |> assign(:data, data) |> assign(:errors, errors)}
  end

  def handle_event("next", %{"setup" => params}, socket) do
    data = maybe_normalize_data(Map.merge(socket.assigns.data, params))

    case validate_step(socket.assigns.step, data, socket.assigns.disk_size_bytes) do
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
    data = maybe_normalize_data(Map.merge(socket.assigns.data, params))

    case validate_all_steps(data, socket.assigns.disk_size_bytes) do
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

  defp display_name_or_username(%{"display_name" => <<_::binary-size(1), _::binary>> = name}), do: name

  defp display_name_or_username(data), do: data[@username_key] || ""

  # Primeiro passo que tem problema: para onde a validação final manda de volta.
  defp error_step(errors) do
    cond do
      Map.has_key?(errors, "community_name") ->
        1

      Map.has_key?(errors, @username_key) or Map.has_key?(errors, "display_name") or
          Map.has_key?(errors, "password") ->
        2

      true ->
        3
    end
  end

  defp exceeds_disk?(_quota_gb, nil), do: false

  defp exceeds_disk?(quota_gb, disk_size_bytes) do
    {gb, ""} = Integer.parse(quota_gb)
    gb * @gigabyte > disk_size_bytes
  end

  # Espaço livre no volume do storage, melhor esforço (`df` POSIX). Falhou?
  # O número simplesmente não aparece: é conforto, não requisito.
  # O espaço livre do disco para o passo 1: a mesma leitura da interface
  # (`TainaWeb.Disk`), sem parsing duplicado de `df`.
  defp free_space do
    case Disk.stats() do
      {:ok, %{free_bytes: free}} -> free
      {:error, _reason} -> nil
    end
  end

  defp limite_text(%{"storage_quota" => "limite", "quota_gb" => gb}), do: "#{gb} GB"
  defp limite_text(_data), do: gettext("o disco inteiro")

  defp maybe_normalize_data(data) do
    case data[@username_key] do
      nil -> data
      username -> Map.put(data, @username_key, username |> String.trim() |> String.downcase())
    end
  end

  # Espelha os `validate_length` do servidor (`Tekoa`: nome 3 a 100; `Ava`:
  # display_name até 80). Vazio não acusa aqui: presença (ou opcionalidade)
  # cuida disso.
  defp maybe_validate_length_in(errors, data, key, range, message) do
    value = data[key] || ""

    if String.trim(value) != "" and String.length(value) not in range,
      do: Map.put(errors, key, message),
      else: errors
  end

  defp maybe_validate_password(errors, data) do
    if String.length(data["password"] || "") < 8,
      do: Map.put(errors, "password", gettext("a senha precisa de pelo menos 8 caracteres")),
      else: errors
  end

  defp maybe_validate_presence(errors, data, key, message) do
    if String.trim(data[key] || "") == "", do: Map.put(errors, key, message), else: errors
  end

  # O username é chave de acesso (e semente do handle federado): normaliza no
  # cliente como o servidor normaliza (`Ava.normalize_username/1`), antes de
  # validar. "João" ou "ana clara" falham no campo, não no POST.
  @username_format ~r/^[a-z0-9._-]+$/

  # Espelha `Ava.maybe_validate_username/1` (3 a 50 caracteres, só minúsculas,
  # números, ponto, hífen e _): o erro de formato aparece no campo aqui.
  defp maybe_validate_username(errors, data) do
    username = data[@username_key] || ""

    cond do
      username == "" ->
        Map.put(errors, @username_key, gettext("escolha um nome de usuário"))

      String.length(username) not in 3..50 ->
        Map.put(errors, @username_key, gettext("de 3 a 50 caracteres"))

      not Regex.match?(@username_format, username) ->
        Map.put(errors, @username_key, gettext("Use só letras minúsculas, números, ponto, hífen ou _, sem espaços."))

      true ->
        errors
    end
  end

  defp positive_integer?(value) do
    case Integer.parse(value) do
      {n, ""} -> n > 0
      _other -> false
    end
  end

  # Formulário mínimo só para o rádio do limite: `to_form` com o valor atual
  # faz o `radio_card` refletir a escolha (o `used_input?` vê o param).
  defp quota_form(data) do
    Phoenix.Component.to_form(%{"storage_quota" => data["storage_quota"]}, as: :setup)
  end

  # Resumo do board ("Quilombo do Café, quem cuida é Ana. Disco interno,
  # limite: o disco inteiro."): o nome de exibição quando existe, o username
  # como reserva.
  defp resumo(data) do
    gettext("%{community}, quem cuida é %{quem}. Disco interno, limite: %{limite}.",
      community: data["community_name"],
      quem: display_name_or_username(data),
      limite: limite_text(data)
    )
  end

  defp step_from_passo(passo, current) when is_binary(passo) do
    case Integer.parse(passo) do
      {step, ""} when step in 1..3 -> step
      _other -> current
    end
  end

  defp step_from_passo(_passo, current), do: current

  defp validate_all_steps(data, disk_size_bytes) do
    1
    |> validate_step(data, disk_size_bytes)
    |> Map.merge(validate_step(2, data, disk_size_bytes))
    |> Map.merge(validate_step(3, data, disk_size_bytes))
  end

  defp validate_quota(%{"storage_quota" => "limite"} = data, disk_size_bytes) do
    quota_gb = data["quota_gb"] || ""

    cond do
      not positive_integer?(quota_gb) ->
        %{"quota_gb" => gettext("O limite precisa ser um número de GB maior que zero.")}

      exceeds_disk?(quota_gb, disk_size_bytes) ->
        disk_gb = div(disk_size_bytes, @gigabyte)
        %{"quota_gb" => gettext("O disco tem %{gb} GB. Escolha um limite menor.", gb: disk_gb)}

      true ->
        %{}
    end
  end

  defp validate_quota(_data, _disk_size_bytes), do: %{}

  defp validate_step(1, data, _disk_size_bytes) do
    %{}
    |> maybe_validate_presence(data, "community_name", gettext("dê um nome à comunidade"))
    |> maybe_validate_length_in(data, "community_name", 3..100, gettext("de 3 a 100 caracteres"))
  end

  defp validate_step(2, data, _disk_size_bytes) do
    %{}
    |> maybe_validate_username(data)
    |> maybe_validate_length_in(data, "display_name", 0..80, gettext("de no máximo 80 caracteres"))
    |> maybe_validate_password(data)
  end

  # A escolha exige GB inteiro e positivo, sem ultrapassar o disco disponível.
  defp validate_step(3, data, disk_size_bytes), do: validate_quota(data, disk_size_bytes)

  defp validate_step(_step, _data, _disk_size_bytes), do: %{}

  @impl true
  def render(assigns) do
    # O estado da escolha de limite vem do rádio (igual ao HTML), via
    # FormField, que é o que o `radio_card` entende.
    assigns = assign(assigns, :quota_form, quota_form(assigns.data))

    ~H"""
    <Layouts.auth flash={@flash}>
      <div :if={@step == 1} class="col flex-1">
        <div class="col gap-3 mt-4 mb-6">
          <.steps current={1} label={gettext("Boas-vindas")} />
          <h1 id="step-heading-1" tabindex="-1" phx-mounted={JS.focus()} class="type-h1">
            {gettext("Boas-vindas à Tainá")}
          </h1>
          <p class="type-body text-secondary">
            {gettext("A estrela da manhã da sua comunidade. Arquivos e fotos da comunidade, guardados com você.")}
          </p>
        </div>

        <.connection_notice :if={@secure_connection? == false} />

        <form id="setup-step-1" phx-change="validate" phx-submit="next" class="col gap-6 flex-1">
          <.field
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
          <.button type="submit" kind="primary" class="w-full" phx-disable-with={gettext("Começar...")}>
            {gettext("Começar")}
          </.button>
        </form>
      </div>

      <div :if={@step == 2} class="col flex-1">
        <div class="col gap-3 mt-4 mb-6">
          <.steps current={2} label={gettext("Quem cuida")} />
          <h1 id="step-heading-2" tabindex="-1" phx-mounted={JS.focus()} class="type-h1">
            {gettext("Quem cuida da comunidade")}
          </h1>
          <p class="type-body text-secondary">
            {gettext("Você é quem vai cuidar da máquina da comunidade. Guarde bem este acesso.")}
          </p>
        </div>

        <.connection_notice :if={@secure_connection? == false} />

        <form id="setup-step-2" phx-change="validate" phx-submit="next" class="col gap-5 flex-1">
          <.field
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
          <.field
            label={gettext("Nome de exibição (opcional)")}
            name="setup[display_name]"
            id="setup_display_name"
            value={@data["display_name"]}
            placeholder={gettext("ex.: Ana Oliveira")}
            help={gettext("Como seu nome aparece para a comunidade.")}
          />
          <.field
            label={gettext("Senha")}
            kind="password"
            name="setup[password]"
            id="setup_password"
            value={@data["password"]}
            placeholder={gettext("mínimo 8 caracteres")}
            help={gettext("Use uma frase longa que só você lembra.")}
            autocomplete="new-password"
            errors={List.wrap(@errors["password"])}
          >
            <:trailing><.password_toggle target="setup_password" /></:trailing>
          </.field>
          <div class="flex-1"></div>
          <.button type="submit" kind="primary" class="w-full" phx-disable-with={gettext("Continuar...")}>
            {gettext("Continuar")}
          </.button>
        </form>
      </div>

      <div :if={@step == 3} class="col flex-1">
        <div class="col gap-3 mt-4 mb-6">
          <.steps current={3} label={gettext("Armazenamento")} />
          <h1 id="step-heading-3" tabindex="-1" phx-mounted={JS.focus()} class="type-h1">
            {gettext("O disco da comunidade")}
          </h1>
          <p class="type-body text-secondary">
            {gettext("Este é o disco da comunidade. Ele é escolhido na instalação da caixa e não pode ser trocado por aqui.")}
          </p>
        </div>

        <.connection_notice :if={@secure_connection? == false} />

        <form
          id="setup-step-3"
          phx-change="validate"
          phx-submit="final"
          phx-trigger-action={@trigger_submit}
          action={~p"/setup"}
          method="post"
          class="col gap-4 flex-1"
        >
          <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
          <input type="hidden" name="setup[community_name]" value={@data["community_name"]} />
          <input type="hidden" name="setup[username]" value={@data["username"]} />
          <input type="hidden" name="setup[display_name]" value={@data["display_name"]} />
          <input type="hidden" name="setup[password]" value={@data["password"]} />

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

          <div class="col gap-3">
            <p class="type-label">{gettext("Quanto do disco a comunidade pode usar")}</p>
            <.radio_card
              field={@quota_form[:storage_quota]}
              value="inteiro"
              label={gettext("O disco inteiro (recomendado)")}
            />
            <.radio_card
              field={@quota_form[:storage_quota]}
              value="limite"
              label={gettext("Um limite")}
            />
            <.field
              :if={@data["storage_quota"] == "limite"}
              label={gettext("Limite em GB")}
              name="setup[quota_gb]"
              id="setup_quota_gb"
              value={@data["quota_gb"]}
              placeholder={gettext("ex.: 50")}
              help={gettext("Em GB. Vale para toda a comunidade.")}
              inputmode="numeric"
              errors={List.wrap(@errors["quota_gb"])}
            />
          </div>

          <.card class="mt-2">
            <p class="type-overline text-muted mb-2">{gettext("Resumo")}</p>
            <p class="type-body">{resumo(@data)}</p>
            <p class="type-body-sm text-muted">{gettext("Quem cuida pode mudar o limite depois.")}</p>
          </.card>

          <div class="flex-1"></div>

          <.button type="submit" kind="primary" class="w-full" phx-disable-with={gettext("Criando...")}>
            {gettext("Criar a nuvem da comunidade")}
          </.button>
        </form>
      </div>
    </Layouts.auth>
    """
  end
end
