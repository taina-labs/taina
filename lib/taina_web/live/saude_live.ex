defmodule TainaWeb.SaudeLive do
  @moduledoc """
  Saúde da comunidade (RFC_003 seção 6, camada 2): o estado da caixa em
  quatro linhas de status, ícone e palavra juntos, nunca só cor.

  Boards do Penpot (docs/web-revamp-spec.md 6.4): morador
  cc1037dc-e8ab-80cc-8008-d5e1a7913c2f, zelador cc1037dc-e8ab-80cc-8008-d5e1ab4909e2,
  atenção cc1037dc-e8ab-80cc-8008-d5e1b8c51263 e Web
  cc1037dc-e8ab-80cc-8008-d5eaeec2de68. O board `atenção` cobre também o
  problema: disco quase cheio é atenção (âmbar), backup que falhou é problema
  (vermelho), e a caixa segue no ar: ninguém perdeu arquivo.

  Não é a tela de limite (essa é o `StorageLive`): aqui são vereditos do
  presente, sem gráfico, sem histórico, sem exportação. Quem não cuida da
  máquina lê quem cuida (pelo nome, do Moradores); quando algo pede atenção,
  a saída é falar com quem cuida; quem cuida lê a própria parte e ganha o
  passo "Fazer backup agora" quando o destino está configurado. A verificação
  de atualizações é opt-in e desligada por padrão (soberana, RFC_003 D6, ver
  `Taina.Nhaman.Update`): o mount decide só o estado barato (desligada, ou
  "verificando") e, quando conectado, uma `Task` busca a resposta e entra por
  `handle_info`.
  """

  use TainaWeb, :live_view

  alias Taina.Maraca
  alias Taina.Nhaman.Backup
  alias Taina.Nhaman.Update
  alias Taina.Ybira
  alias TainaWeb.Layouts
  alias TainaWeb.Saude

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    # Estado barato do mount: desligada usa o status direto (sem rede);
    # ligada, o GET fica para a Task (abaixo), com "verificando" no lugar.
    update_status = if Update.enabled?(), do: checking_status(), else: Update.status()

    socket =
      socket
      |> assign(:page_title, gettext("Saúde da comunidade"))
      |> assign(:load_error, false)
      |> assign(:update_status, update_status)
      |> assign_painel(scope)

    socket =
      if connected?(socket) and Update.enabled?() do
        me = self()

        {:ok, _pid} = Task.start_link(fn -> send(me, {:update_status, Update.status()}) end)

        socket
      else
        socket
      end

    {:ok, socket}
  end

  # Resposta do GET opt-in: troca a linha "verificando" pelo resultado de
  # verdade, sem reconsultar o banco (o resto do painel fica como está).
  @impl true
  def handle_info({:update_status, status}, socket) do
    painel = socket.assigns.painel && %{socket.assigns.painel | update_status: status}

    {:noreply,
     socket
     |> assign(:update_status, status)
     |> assign(:painel, painel)}
  end

  @impl true
  def handle_event("run-backup", _params, socket) do
    if Maraca.zelador?(socket.assigns.current_scope.ava) and Backup.enabled?() do
      # Dispara o mesmo worker do backup agendado: a fila cuida do trabalho
      # pesado (pg_dump + tar.gz) fora do request, e a fila já é o caminho de
      # produção de `Taina.Nhaman.Backup.run/1`.
      case Oban.insert(Taina.Nhaman.Workers.Backup.new(%{})) do
        {:ok, _job} ->
          :ok = Maraca.record_event(socket.assigns.current_scope, :backup_scheduled, %{})
          {:noreply, put_flash(socket, :info, gettext("Backup a caminho. Volte daqui a pouco para conferir."))}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Não foi possível agendar o backup agora."))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("retry", _params, socket) do
    {:noreply, assign_painel(socket, socket.assigns.current_scope)}
  end

  # Carrega os fatos que vêm do banco (disco, moradores) mais o backup e o
  # estado da verificação, sem derrubar a tela: se falharem, o cartão de erro
  # assume o lugar (sem flash duplicado).
  defp assign_painel(socket, scope) do
    with {:ok, stats} <- Ybira.storage_stats(scope),
         {:ok, members} <- Maraca.list_members(scope) do
      socket
      |> assign(:painel, %{
        stats: stats,
        backup: Backup.last_backup(),
        update_status: socket.assigns.update_status,
        zelador?: Maraca.zelador?(scope.ava),
        zeladores: zelador_names(members)
      })
      |> assign(:load_error, false)
    else
      _error ->
        socket
        |> assign(:painel, nil)
        |> assign(:load_error, true)
    end
  end

  # --- core puro: dados -> dados ---

  # O modelo do corpo: nil (a carga falhou) não desenha nada além do cartão
  # de erro; senão, as linhas, o rodapé e o botão do backup, decididos de uma
  # vez (spec 1.3: qual estado renderizar é decisão pura do dado).
  defp body_model(nil), do: nil

  defp body_model(painel) do
    rows = saude_rows(painel)

    %{rows: rows, footer: care_footer(painel, rows), backup_button: backup_button?(painel)}
  end

  # As quatro linhas do board, na ordem: backup, espaço, atualização e a
  # caixa no ar. Linha do board não leva detalhe (Detail: none).
  defp saude_rows(%{stats: stats, backup: backup, update_status: update_status}) do
    [
      backup_row(backup),
      disk_row(stats, backup),
      update_row(update_status),
      %{state: "ok", title: gettext("Tudo no ar")}
    ]
  end

  # Em dia é "Backup em dia"; caixa nova (nunca houve backup) é atenção e
  # backup ilegível é problema (o board `atenção` pinta o falhado de
  # vermelho). A palavra nasce no resumo da Saúde, o mesmo veredito do hub.
  defp backup_row({:ok, _guardou}), do: %{state: "ok", title: gettext("Backup em dia")}

  defp backup_row({:error, reason} = backup) do
    %{line: title} = backup_verdict(backup)

    %{state: backup_state(reason), title: title}
  end

  # O veredito do backup, isolado do disco: com cota nil o disco não chama
  # atenção, então a linha do resumo é só do backup (`TainaWeb.Saude`).
  defp backup_verdict(backup) do
    Saude.summary_line(%{storage: %{used_bytes: 0, quota_bytes: nil}, backup: backup})
  end

  defp backup_state(reason) when reason in [:none, :no_dir], do: "attention"
  defp backup_state(_reason), do: "problem"

  # Sem limite não há o que estourar (`Saude.disk_attention?/1`): o espaço é
  # de sobra. Na atenção, a palavra é a do resumo (o disco fala primeiro,
  # doc do Saude), seja qual for o backup.
  defp disk_row(stats, backup) do
    if Saude.disk_attention?(stats) do
      %{state: "attention", title: Saude.summary_line(%{storage: stats, backup: backup}).line}
    else
      %{state: "ok", title: gettext("Espaço de sobra")}
    end
  end

  # A verificação de atualização (opt-in, soberana): "em dia" é da caixa que
  # verificou e está na mais recente. Os outros estados dizem o que se sabe,
  # sem fingir - nem "em dia" quem desligou a verificação ou não conseguiu
  # verificar agora.
  defp update_row(%{result: :up_to_date}), do: %{state: "ok", title: gettext("Atualizações em dia")}

  defp update_row(%{result: {:update_available, _latest}}) do
    %{state: "attention", title: gettext("Atualização disponível")}
  end

  defp update_row(%{result: :checking}), do: %{state: "unknown", title: gettext("Verificando atualização")}
  defp update_row(%{result: :check_off}), do: %{state: "unknown", title: gettext("Verificação desligada")}

  defp update_row(%{result: result}) when result in [:unavailable, :unknown] do
    %{state: "unknown", title: gettext("Verificação falhou")}
  end

  # O botão do backup (board zelador): só para quem cuida da máquina e só
  # quando o destino está configurado - botão que não funciona é beco sem
  # saída.
  defp backup_button?(%{zelador?: true}), do: Backup.enabled?()
  defp backup_button?(_painel), do: false

  # O rodapé do board: quem não cuida lê quem cuida, pelo nome (e o cuidado é
  # da máquina, não dos arquivos); quando algo pede atenção, a saída é falar
  # com quem cuida (e o alívio: ninguém perdeu arquivo); quem cuida lê a
  # própria parte.
  defp care_footer(%{zelador?: true}, _rows) do
    gettext("Você cuida da nuvem. O backup é a sua parte; os arquivos continuam de cada um.")
  end

  defp care_footer(%{zeladores: zeladores}, rows) do
    if Enum.any?(rows, &(&1.state != "ok")),
      do: gettext("Vale falar com quem cuida da nuvem. Ninguém perdeu arquivo."),
      else: care_names_line(zeladores)
  end

  # "Quem cuida da nuvem é a Ana" (board): sem o artigo, o nome serve para
  # qualquer pessoa.
  defp care_names_line([name]) do
    gettext("Quem cuida da nuvem é %{name}. Cuida da máquina, não dos arquivos.", name: name)
  end

  defp care_names_line([_first | _rest] = names) do
    gettext("Quem cuida da nuvem: %{names}. Cuidam da máquina, não dos arquivos.",
      names: list_in_portuguese(names)
    )
  end

  # A última zeladoria é guardada pelo kernel, mas a frase não vai quebrar se
  # um dia não houver nome para ler.
  defp care_names_line([]), do: gettext("Vale falar com quem cuida da nuvem. Ninguém perdeu arquivo.")

  # Quem cuida da máquina, pelo nome: só quem está ativo. Conta desativada
  # desativada está, não é gente cuidando da caixa agora.
  defp zelador_names(members) do
    members
    |> Enum.filter(&(&1.papel == :zelador and is_nil(&1.deactivated_at)))
    |> Enum.map(&person_name/1)
  end

  defp checking_status, do: %{running: Update.running_version(), result: :checking}

  # --- shell imperativo: assign/render ---

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.page flash={@flash} title={@page_title} back={~p"/"}>
      <.saude_body load_error={@load_error} painel={@painel} />
    </Layouts.page>
    """
  end

  @doc """
  Corpo da Saúde: componente puro, recebe o resumo carregado e devolve HEEx.
  As linhas são `status_line` (estado pelo dado, nunca só cor, spec 1.7); o
  cartão de erro assume quando a nuvem não responde.
  """
  attr :load_error, :boolean, required: true
  attr :painel, :map, default: nil

  def saude_body(assigns) do
    assigns = assign(assigns, :saude, body_model(assigns.painel))

    ~H"""
    <div class="col gap-6">
      <.error_card
        :if={@load_error}
        title={gettext("Não conseguimos falar com a nuvem agora.")}
        retry_event="retry"
      />

      <div :if={@saude} class="col gap-4">
        <p class="type-overline text-muted">{gettext("ESTADO DA NUVEM")}</p>

        <div class="col">
          <div :for={{row, index} <- Enum.with_index(@saude.rows)}>
            <hr :if={index > 0} class="divider" />
            <.status_line state={row.state} title={row.title} />
          </div>
        </div>

        <.button :if={@saude.backup_button} kind="primary" class="self-start" phx-click="run-backup">
          {gettext("Fazer backup agora")}
        </.button>

        <p class="type-body-sm text-secondary">{@saude.footer}</p>
      </div>
    </div>
    """
  end
end
