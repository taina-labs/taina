defmodule TainaWeb.StorageLive do
  @moduledoc """
  Armazenamento (docs/web-revamp-spec.md 6.4): o limite da comunidade, um só,
  vale para a caixa inteira.

  Boards do Penpot: morador cc1037dc-e8ab-80cc-8008-d5e2660cc8ac, zelador
  cc1037dc-e8ab-80cc-8008-d5e272d5b62e (com a folha "Limite de espaço") e
  disco inteiro 88db615f-12f9-80b9-8008-d63207dbf310. O card "Espaço da
  comunidade" leva o total; "O que ocupa espaço" reparte os bytes por zona
  (Casas, Praça, Lixeira, `Ybira.storage_stats_by_zone/1`) e a soma fecha com
  o total do card.

  Quem não cuida da máquina lê quem escolhe o limite, pelo nome; quem cuida
  ganha "Mudar limite": o disco inteiro (cota `nil`) ou um limite em GB
  (`Maraca.update_tekoa_quota/2`, que aceita `nil`). Não existe limite por
  pessoa, nem aqui nem em outra tela.
  """

  use TainaWeb, :live_view

  alias Taina.Maraca
  alias Taina.Ybira
  alias TainaWeb.Disk
  alias TainaWeb.Layouts

  @gigabyte 1024 * 1024 * 1024

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Armazenamento"))
     |> assign(:show_quota_sheet, false)
     |> assign(:quota_choice, nil)
     |> assign(:zelador?, Maraca.zelador?(socket.assigns.current_scope.ava))
     |> load_stats()}
  end

  @impl true
  def handle_event("retry", _params, socket) do
    {:noreply, load_stats(socket)}
  end

  # "Falar com quem cuida" (cartão de erro): a Saúde é a tela que diz quem
  # cuida da máquina. Web não abre conversa com ninguém.
  def handle_event("contact", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/saude")}
  end

  # A folha abre com a escolha que a cota atual indica (board zelador): com
  # limite é o "Definir um limite"; sem, o "Usar o disco inteiro".
  def handle_event("open-quota-sheet", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_quota_sheet, true)
     |> assign(:quota_choice, quota_choice(socket.assigns.stats))}
  end

  def handle_event("close-quota-sheet", _params, socket) do
    {:noreply, assign(socket, :show_quota_sheet, false)}
  end

  # O rádio manda a escolha; o campo do limite só existe no "Definir um
  # limite" (o servidor decide, sem JS de visibilidade).
  def handle_event("select-choice", %{"quota" => %{"choice" => choice}}, socket) do
    {:noreply, assign(socket, :quota_choice, validate_choice(choice))}
  end

  def handle_event("select-choice", _params, socket), do: {:noreply, socket}

  def handle_event("update-quota", %{"quota" => quota}, socket) do
    case quota_bytes(quota["choice"], quota["gigabytes"], socket.assigns.disk_gb) do
      {:ok, bytes} ->
        case Maraca.update_tekoa_quota(socket.assigns.current_scope, bytes) do
          {:ok, _tekoa} ->
            {:noreply,
             socket
             |> assign(:show_quota_sheet, false)
             |> put_flash(:info, gettext("Limite atualizado."))
             |> load_stats()}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, gettext("Não foi possível salvar agora. Tente de novo."))}
        end

      # Número inteiro, sem vírgula, dentro do disco: "50" vale, "50,5",
      # "" e "999" (acima do disco) não. Erro de escrita e erro de
      # salvamento são falas diferentes.
      :error ->
        {:noreply, put_flash(socket, :error, quota_error(socket.assigns.disk_gb))}
    end
  end

  # Carrega os fatos sem derrubar a tela: se o domínio falhar, o cartão de
  # erro com "Tentar de novo" assume o lugar (sem flash duplicado).
  defp load_stats(socket) do
    scope = socket.assigns.current_scope

    with {:ok, stats} <- Ybira.storage_stats(scope),
         {:ok, zones} <- Ybira.storage_stats_by_zone(scope),
         {:ok, members} <- Maraca.list_members(scope) do
      socket
      |> assign(:stats, Map.put(stats, :disk_bytes, Disk.total_bytes()))
      |> assign(:disk_gb, disk_gb())
      |> assign(:zones, zones)
      |> assign(:caretakers, caretaker_names(members))
      |> assign(:load_error, false)
    else
      _error ->
        socket
        |> assign(:stats, nil)
        |> assign(:zones, nil)
        |> assign(:caretakers, [])
        |> assign(:disk_gb, nil)
        |> assign(:load_error, true)
    end
  end

  # --- core puro: dados -> dados ---

  # A escolha que a folha abre marcada: a cota de hoje é o "Definir um
  # limite"; sem cota (disco inteiro), o "Usar o disco inteiro".
  defp quota_choice(%{quota_bytes: quota}) when is_integer(quota), do: "limite"
  defp quota_choice(_stats), do: "inteiro"

  defp validate_choice("inteiro"), do: "inteiro"
  defp validate_choice("limite"), do: "limite"
  defp validate_choice(_other), do: nil

  # A escolha do board vira bytes: "inteiro" remove o limite (cota `nil`, o
  # changeset da Tekoa aceita); "limite" valida o campo, com o teto do disco
  # quando a tela sabe o tamanho dele. Decisão pura.
  defp quota_bytes("inteiro", _gigabytes, _disk_gb), do: {:ok, nil}
  defp quota_bytes("limite", gigabytes, disk_gb), do: parse_gigabytes(gigabytes, disk_gb)
  defp quota_bytes(_choice, _gigabytes, _disk_gb), do: :error

  defp parse_gigabytes(gigabytes, disk_gb) when is_binary(gigabytes) do
    case Integer.parse(gigabytes) do
      {gigabytes, ""} when gigabytes > 0 ->
        if is_integer(disk_gb) and gigabytes > disk_gb,
          do: :error,
          else: {:ok, gigabytes * @gigabyte}

      _other ->
        :error
    end
  end

  defp parse_gigabytes(_nil, _disk_gb), do: :error

  defp quota_error(disk_gb) when is_integer(disk_gb) do
    gettext("Escreva um número inteiro de GB, de 1 a %{max}.", max: disk_gb)
  end

  defp quota_error(_disk_gb), do: gettext("Escreva um número inteiro de GB, sem vírgula.")

  # O teto do campo: o disco inteiro em GB (o board diz "de 1 a 256").
  defp disk_gb do
    case Disk.total_bytes() do
      total when is_integer(total) and total > 0 -> div(total, @gigabyte)
      _other -> nil
    end
  end

  defp quota_help(disk_gb) when is_integer(disk_gb) do
    gettext("Em GB, de 1 a %{max}.", max: disk_gb)
  end

  defp quota_help(_disk_gb), do: gettext("Um número inteiro, em GB.")

  # O valor do campo quando a folha abre: o limite de hoje, em GB.
  defp quota_gb(%{quota_bytes: quota}) when is_integer(quota), do: div(quota, @gigabyte)
  defp quota_gb(_stats), do: nil

  # As linhas do "O que ocupa espaço" (board), na ordem: casas (a soma das
  # casas de cada morador, sem nomes), praça e lixeira. A soma fecha com o
  # total do card (doc do `Ybira.storage_stats_by_zone/1`).
  defp zone_rows(%{casa: casas, praca: praca, lixeira: lixeira}) do
    [
      %{mark: "casa", title: gettext("Casas (de cada morador)"), bytes: casas},
      %{mark: "praca", title: gettext("Praça"), bytes: praca},
      %{mark: "lixeira", title: gettext("Lixeira"), bytes: lixeira}
    ]
  end

  # Quem cuida da máquina, pelo nome: só quem está ativo. Conta desativada
  # desativada está, não é gente cuidando da caixa agora.
  defp caretaker_names(members) do
    members
    |> Enum.filter(&(&1.papel == :zelador and is_nil(&1.deactivated_at)))
    |> Enum.map(&(&1.display_name || &1.username))
  end

  # Lista de nomes em pt-BR: "Ana", "Ana e Bruno", "Ana, Bruno e Carol".
  defp list_in_portuguese([name]), do: name
  defp list_in_portuguese([first, second]), do: "#{first} #{gettext("e")} #{second}"

  defp list_in_portuguese(names) do
    [last | rest] = Enum.reverse(names)
    Enum.join(Enum.reverse(rest), ", ") <> " #{gettext("e")} #{last}"
  end

  # --- shell imperativo: assign/render ---

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.page flash={@flash} title={@page_title} back={~p"/"}>
      <.storage_body
        load_error={@load_error}
        stats={@stats}
        zones={@zones}
        caretakers={@caretakers}
        zelador?={@zelador?}
        show_quota_sheet={@show_quota_sheet}
        quota_choice={@quota_choice}
        disk_gb={@disk_gb}
      />
    </Layouts.page>
    """
  end

  @doc """
  Corpo do Armazenamento: componente puro, recebe os fatos carregados e
  devolve HEEx. É aqui que a tela escolhe entre cartão de erro, card +
  repartição por zona (morador: a frase de quem escolhe; zelador: "Mudar
  limite" e a folha do limite, boards zelador/disco inteiro).
  """
  attr :load_error, :boolean, required: true
  attr :stats, :map, default: nil
  attr :zones, :map, default: nil
  attr :caretakers, :list, default: []
  attr :zelador?, :boolean, required: true
  attr :show_quota_sheet, :boolean, required: true
  attr :quota_choice, :string, default: nil
  attr :disk_gb, :integer, default: nil, doc: "teto do campo em GB (nil = disco desconhecido)"

  def storage_body(assigns) do
    # A escolha vive no rádio (igual ao HTML): o to_form reflete o valor e o
    # card marca o selecionado, o mesmo falar do Convidar.
    assigns = assign(assigns, :form, to_form(%{"choice" => assigns.quota_choice || ""}, as: :quota))

    ~H"""
    <.error_card
      :if={@load_error}
      title={gettext("Não conseguimos falar com a nuvem agora.")}
      retry_event="retry"
      contact_event="contact"
    />

    <div :if={@stats} class="col gap-6">
      <.storage_card stats={@stats} detail="full" />

      <section class="col gap-3">
        <h2 class="type-overline text-muted">{gettext("O que ocupa espaço")}</h2>
        <ul class="list">
          <.list_row :for={row <- zone_rows(@zones)} kind="civic" title={row.title} meta={format_bytes(row.bytes)}>
            <:leading><.service_square mark={row.mark} /></:leading>
          </.list_row>
        </ul>
      </section>

      <.button :if={@zelador?} kind="secondary" class="w-full" phx-click="open-quota-sheet">
        {gettext("Mudar limite")}
      </.button>

      <p :if={not @zelador? and @caretakers != []} class="type-body-sm text-secondary">
        {gettext("Quem cuida da caixa escolhe quanto do disco a comunidade usa. Hoje, isso é com %{names}.",
          names: list_in_portuguese(@caretakers))
        }
      </p>
    </div>

    <.sheet
      :if={@zelador?}
      id="quota-sheet"
      show={@show_quota_sheet}
      on_cancel="close-quota-sheet"
      title={gettext("Limite de espaço")}
      kind="content"
    >
      <form id="quota-form" phx-submit="update-quota" phx-change="select-choice" class="col gap-4">
        <.radio_card
          field={@form[:choice]}
          value="inteiro"
          label={gettext("Usar o disco inteiro")}
          description={gettext("A comunidade usa todo o disco.")}
        />
        <.radio_card field={@form[:choice]} value="limite" label={gettext("Definir um limite")} />
        <.field
          :if={@quota_choice == "limite"}
          label={gettext("Limite (GB)")}
          name="quota[gigabytes]"
          id="quota_gigabytes"
          value={quota_gb(@stats)}
          help={quota_help(@disk_gb)}
          inputmode="numeric"
        />
        <.button type="submit" kind="primary" class="w-full">{gettext("Salvar")}</.button>
      </form>
    </.sheet>
    """
  end
end
