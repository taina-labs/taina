defmodule TainaWeb.SaudeLive do
  @moduledoc """
  Saúde da comunidade (RFC_003 seção 6, camada 2): o estado da máquina em frases
  simples, para a comunidade inteira ler.

  Não é a tela de cota (essa é o `StorageLive`, que fica como está): aqui são
  fatos do presente, sem gráfico, sem histórico, sem exportação. Cuidado, não
  controle: avisos são ambientes, ícone e frase juntos, nunca só cor, sem
  vermelho de urgência. Morador lê tudo; quem cuida da máquina ganha o próximo
  passo (fazer um backup agora) onde ele existe.

  A verificação de atualizações é opt-in e desligada por padrão (soberana,
  RFC_003 D6, ver `Taina.Nhaman.Update`); o status é computado uma vez por
  mount (`assign_new`, sem re-GET na passagem HTTP -> WebSocket).
  """

  use TainaWeb, :live_view

  alias Taina.Maraca
  alias Taina.Maraca.Ava
  alias Taina.Nhaman.Backup
  alias Taina.Nhaman.Update
  alias Taina.Scope
  alias Taina.Ybira
  alias TainaWeb.Layouts

  # Limite "acabando" do disco: 90% da cota. Aviso ambiente, não alarme.
  @disk_warning_percent 90

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    socket =
      socket
      |> assign(:page_title, gettext("Saúde da comunidade"))
      |> assign(:load_error, false)
      |> assign_new(:update_status, fn -> Update.status() end)
      |> assign_painel(scope)

    {:ok, socket}
  end

  @impl true
  def handle_event("run-backup", _params, socket) do
    if Maraca.zelador?(socket.assigns.current_scope.ava) and Backup.enabled?() do
      # Dispara o mesmo worker do backup agendado: a fila cuida do trabalho
      # pesado (pg_dump + tar.gz) fora do request, e a fila já é o caminho de
      # produção de `Taina.Nhaman.Backup.run/1`.
      case Oban.insert(Taina.Nhaman.Workers.Backup.new(%{})) do
        {:ok, _job} ->
          {:noreply,
           Phoenix.LiveView.put_flash(socket, :info, gettext("Backup a caminho. Volte daqui a pouco para conferir."))}

        {:error, _reason} ->
          {:noreply, Phoenix.LiveView.put_flash(socket, :error, gettext("Não foi possível agendar o backup agora."))}
      end
    else
      {:noreply, socket}
    end
  end

  # Carrega os fatos que vêm do banco (disco, moradores, jobs) sem derrubar a
  # tela: se falharem, flash e empty_state assumem o lugar. Backup e
  # atualização têm degradação própria, cada linha diz o seu estado.
  defp assign_painel(socket, scope) do
    with {:ok, stats} <- Ybira.storage_stats(scope),
         {:ok, members} <- Maraca.list_members(scope) do
      socket
      |> assign(:painel, %{
        stats: stats,
        members: members,
        jobs: Ybira.pending_job_counts(),
        last_backup: Backup.last_backup(),
        update_status: socket.assigns.update_status
      })
      |> assign(:load_error, false)
    else
      _error ->
        socket
        |> assign(:painel, nil)
        |> assign(:load_error, true)
        |> Phoenix.LiveView.put_flash(
          :error,
          gettext("Não foi possível carregar a saúde agora. Tente recarregar em instantes.")
        )
    end
  end

  # --- core puro: dados -> dados ---

  # As linhas do painel, na ordem do RFC_003 seção 6. Cada linha é um fato do
  # presente; contagem zerada não mostra linha ("0" não é fato, é número).
  defp painel_rows(%Scope{} = scope, %{
         stats: stats,
         members: members,
         jobs: jobs,
         last_backup: last_backup,
         update_status: update_status
       }) do
    Enum.reject(
      [
        disk_row(stats),
        backup_row(last_backup, scope),
        jobs_row(jobs),
        residents_row(members),
        update_row(update_status),
        identity_row(scope)
      ],
      &is_nil(&1)
    )
  end

  defp disk_row(%{used_bytes: used, quota_bytes: nil}) do
    row("disk", gettext("Disco"), [gettext("%{used} usados. Sem limite definido.", used: format_bytes(used))])
  end

  defp disk_row(%{used_bytes: used, quota_bytes: quota}) when is_integer(quota) do
    free = max(quota - used, 0)

    body = [
      gettext("%{used} usados de %{total}. %{free} livres.",
        used: format_bytes(used),
        total: format_bytes(quota),
        free: format_bytes(free)
      )
    ]

    if quota > 0 and used / quota * 100 >= @disk_warning_percent do
      row("disk", gettext("Disco"), body, gettext("O espaço está acabando."))
    else
      row("disk", gettext("Disco"), body)
    end
  end

  defp backup_row({:ok, %{at: at, bytes: bytes}}, _scope) do
    row("shield", gettext("Último backup"), [
      gettext("Terminou bem %{quando} (%{size} guardados).", quando: ago(at), size: format_bytes(bytes))
    ])
  end

  # Nenhum backup ainda: o estado dito como fato mais o próximo passo. Para
  # quem cuida da máquina, o passo é um botão (quando o backup está
  # configurado); para quem não cuida, cuidado é de quem cuida, não recusa.
  defp backup_row({:error, reason}, %Scope{} = scope) when reason in [:none, :no_dir] do
    zelador? = Maraca.zelador?(scope.ava)

    body =
      cond do
        zelador? and Backup.enabled?() ->
          [gettext("Nenhum backup ainda."), gettext("Quem cuida da máquina pode fazer um agora.")]

        zelador? ->
          [
            gettext("Nenhum backup ainda."),
            gettext("Quem cuida da máquina ainda não configurou onde guardar os backups.")
          ]

        true ->
          [gettext("Nenhum backup ainda."), gettext("Quem cuida da máquina cuida do backup.")]
      end

    if zelador? and Backup.enabled?(),
      do: row("shield", gettext("Último backup"), body, nil, :run_backup),
      else: row("shield", gettext("Último backup"), body)
  end

  defp backup_row({:error, :unreadable}, _scope) do
    row("shield", gettext("Último backup"), [gettext("Não foi possível ler os backups agora.")])
  end

  # Jobs em espera ou em andamento: contagem com substantivo, zerado não
  # mostra linha (a linha inteira desaparece quando não há trabalho).
  defp jobs_row(%{renditions: renditions, trash_purge: trash_purge}) do
    body =
      []
      |> maybe_append(renditions > 0, fn ->
        ngettext("1 miniatura ainda sendo gerada", "%{count} miniaturas ainda sendo geradas", renditions)
      end)
      |> maybe_append(trash_purge > 0, fn ->
        ngettext("1 expurgo da lixeira em andamento", "%{count} expurgos da lixeira em andamento", trash_purge)
      end)

    if body == [], do: nil, else: row("clock", gettext("Trabalhos da caixa"), body)
  end

  defp residents_row(members) do
    # Moradores de verdade: quem pode entrar. Conta desativada desativada
    # está, não é gente usando a caixa agora.
    active = Enum.filter(members, &is_nil(&1.deactivated_at))

    zeladores =
      active
      |> Enum.filter(&(&1.role == :zelador))
      |> Enum.map(&ava_name/1)

    body = [ngettext("1 morador", "%{count} moradores", length(active))] ++ caretaker_line(zeladores)

    row("user", gettext("Moradores"), body)
  end

  defp update_row(%{running: running, result: :check_off}) do
    row("restore", gettext("Atualização"), [
      gettext("A caixa está na versão %{version}.", version: running),
      gettext("A verificação de atualizações está desligada: a caixa não conversa com a internet por conta própria.")
    ])
  end

  defp update_row(%{running: running, result: :up_to_date}) do
    row("restore", gettext("Atualização"), [
      gettext("A caixa está na versão %{version}, a mais recente.", version: running)
    ])
  end

  defp update_row(%{running: running, result: {:update_available, latest}}) do
    row("restore", gettext("Atualização"), [
      gettext("Há uma versão mais nova (%{latest}). A caixa está na %{version}.", latest: latest, version: running)
    ])
  end

  defp update_row(%{running: running, result: :unavailable}) do
    row("restore", gettext("Atualização"), [
      gettext("Não foi possível verificar atualizações agora. A caixa está na versão %{version}.", version: running)
    ])
  end

  defp update_row(%{result: :unknown}) do
    row("restore", gettext("Atualização"), [
      gettext("Não deu para comparar a versão da caixa com a publicada agora.")
    ])
  end

  defp identity_row(%Scope{} = scope) do
    row("home", gettext("A caixa"), [
      gettext("Esta é a caixa de %{tekoa}.", tekoa: scope.tekoa.name),
      gettext("Vocês acessam por %{address}.", address: box_address())
    ])
  end

  defp row(icon, label, body, warning \\ nil, action \\ nil) do
    %{icon: icon, label: label, body: body, warning: warning, action: action}
  end

  defp maybe_append(list, true, fun), do: list ++ [fun.()]
  defp maybe_append(list, false, _fun), do: list

  defp caretaker_line([]), do: []

  defp caretaker_line(zeladores) do
    [gettext("Quem cuida da máquina: %{names}.", names: list_in_portuguese(zeladores))]
  end

  defp ava_name(%Ava{} = ava), do: ava.display_name || ava.username

  # Lista de nomes em pt-BR: "Ana", "Ana e Bruno", "Ana, Bruno e Carol".
  defp list_in_portuguese([name]), do: name
  defp list_in_portuguese([first, second]), do: "#{first} #{gettext("e")} #{second}"

  defp list_in_portuguese(names) do
    [last | rest] = Enum.reverse(names)
    Enum.join(Enum.reverse(rest), ", ") <> " #{gettext("e")} #{last}"
  end

  # "Quando" do backup (DateTime UTC), o mesmo passo do `relative_time/1` do
  # design system, que só recebe NaiveDateTime.
  defp ago(%DateTime{} = at) do
    days = Date.diff(Date.utc_today(), DateTime.to_date(at))

    cond do
      days <= 0 -> gettext("hoje")
      days == 1 -> gettext("ontem")
      days < 30 -> gettext("há %{count} dias", count: days)
      true -> gettext("há %{count} meses", count: div(days, 30))
    end
  end

  # O endereço pela qual a comunidade alcança a caixa: o host configurado do
  # endpoint (PHX_HOST), não um valor que o navegador inventa.
  defp box_address do
    case TainaWeb.Endpoint.config(:url)[:host] do
      nil -> gettext("endereço não configurado")
      host -> host
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active_tab={:saude}
      storage_stats={assigns[:storage_stats]}
      account_alert={assigns[:account_alert] || false}
    >
      <div class="col gap-6">
        <div class="row gap-3">
          <.service_square service="nhaman" icon="saude" />
          <h1 class="type-h1">{gettext("Saúde da comunidade")}</h1>
        </div>

        <.empty_state
          :if={@load_error}
          icon="alert"
          title={gettext("Não foi possível carregar")}
          hint={gettext("A saúde da caixa não respondeu agora. Tente recarregar em instantes.")}
        />

        <div :if={not @load_error} class="painel-grid">
          <.card :for={row <- painel_rows(@current_scope, @painel)} raised class="col gap-2">
            <div class="row gap-3">
              <.icon name={row.icon} size={20} class="text-muted" />
              <p class="type-label">{row.label}</p>
            </div>
            <p :for={line <- row.body} class="type-body-sm text-secondary">{line}</p>
            <p :if={row.warning} class="row gap-2 type-body-sm text-warning">
              <.icon name="alert" size={16} /> {row.warning}
            </p>
            <.button
              :if={row.action == :run_backup}
              variant="secondary"
              size="sm"
              class="self-start"
              phx-click="run-backup"
            >
              {gettext("Fazer backup agora")}
            </.button>
          </.card>
        </div>

        <.card :if={Maraca.zelador?(@current_scope.ava)}>
          <.link navigate={~p"/painel-do-zelador"} class="row between w-full">
            <span class="row gap-3 type-label">
              <.icon name="disk" size={20} class="text-muted" />
              {gettext("Painel da máquina")}
            </span>
            <.icon name="chevron-right" size={18} class="text-faint" />
          </.link>
          <p class="type-body-sm text-muted mt-2">
            {gettext("Gráficos e trabalhos técnicos da caixa, para quem cuida dela.")}
          </p>
        </.card>
      </div>
    </Layouts.app>
    """
  end
end
