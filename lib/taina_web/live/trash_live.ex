defmodule TainaWeb.TrashLive do
  @moduledoc """
  Lixeira do Documentos (boards "Servico / Ybira Lixeira / padrao"
  cc1037dc-e8ab-80cc-8008-d5e1918978c5 e "vazio" ...d5e19453d049): arquivos e
  pastas apagados nos últimos 30 dias, com a cópia de ensino sobre a janela e
  um "Restaurar" rotulado em cada linha (a pasta volta como unidade, com o
  que foi apagado junto). Sem ação de apagar aqui: a purga definitiva é
  automática (`PurgeTrash`, Oban, 30 dias) e o kernel ainda não expõe a
  exclusão por item; fica para quando o context ganhar `purge_file/2`.
  """

  use TainaWeb, :live_view

  alias Taina.Ybira
  alias TainaWeb.Layouts
  alias Ypy.Ybira.File
  alias Ypy.Ybira.Folder

  # A regra da lixeira em texto usa o mesmo número que o worker usa para
  # expurgar; o aviso de janela fechando é a régua do board ("resta 6 dias").
  @retention_days 30
  @warning_days 5

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, gettext("Documentos")) |> load_trash()}
  end

  defp load_trash(socket) do
    scope = socket.assigns.current_scope

    with {:ok, %{items: items, next_cursor: next_cursor}} <- Ybira.list_trash(scope),
         {:ok, folders} <- Ybira.list_trash_folders(scope) do
      socket
      |> assign(:items, items)
      |> assign(:folders, folders)
      |> assign(:next_cursor, next_cursor)
      |> assign(:load_error, false)
    else
      _error ->
        # Sem beco sem saída: flash com o que houve, e a lixeira com o cartão
        # de erro e a saída ("Tentar de novo").
        socket
        |> assign(:items, [])
        |> assign(:folders, [])
        |> assign(:next_cursor, nil)
        |> assign(:load_error, true)
        |> put_flash(:error, gettext("Não foi possível carregar a lixeira."))
    end
  end

  @impl true
  def handle_event("retry-load", _params, socket), do: {:noreply, load_trash(socket)}

  def handle_event("restore", %{"id" => rkey, "type" => "folder"}, socket) do
    case Ybira.restore_folder(socket.assigns.current_scope, rkey) do
      {:ok, _folder} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Pasta restaurada com o que tinha dentro."))
         |> load_trash()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Não foi possível restaurar a pasta."))}
    end
  end

  def handle_event("restore", %{"id" => rkey}, socket) do
    case Ybira.restore_file(socket.assigns.current_scope, rkey) do
      {:ok, _file} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Arquivo restaurado."))
         |> load_trash()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Não foi possível restaurar o arquivo."))}
    end
  end

  def handle_event("load-more", _params, socket) do
    if cursor = socket.assigns.next_cursor do
      case Ybira.list_trash(socket.assigns.current_scope, after_cursor: cursor) do
        {:ok, %{items: items, next_cursor: next_cursor}} ->
          {:noreply,
           socket
           |> assign(:items, socket.assigns.items ++ items)
           |> assign(:next_cursor, next_cursor)}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Não foi possível carregar mais itens."))}
      end
    else
      {:noreply, socket}
    end
  end

  # O shell inscreve o morador nos eventos do Ava; esta tela não reage a eles
  # (a lixeira se refaz no próximo load_trash), mas precisa ignorar o que não
  # trata.
  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # --- core puro: dados -> dados ---

  defp days_left(file) do
    deleted_days_ago = Date.diff(Date.utc_today(), DateTime.to_date(file.apagado_em))
    max(@retention_days - deleted_days_ago, 0)
  end

  # Meta da linha (board): "PDF, 900 KB, resta 21 dias". Quando a janela
  # fecha, o que acontece vem antes de a linha sumir: "apaga hoje". A pasta
  # não tem tipo nem tamanho; fala o que é.
  defp trash_meta(%File{} = item) do
    prazo(item, "#{file_kind(item.mime)}, #{format_bytes(item.tamanho)}")
  end

  defp trash_meta(%Folder{} = item), do: prazo(item, gettext("Pasta"))

  defp prazo(item, base) do
    left = days_left(item)

    cond do
      left == 0 ->
        base <> ", " <> gettext("apaga hoje")

      left <= @warning_days ->
        base <>
          ", " <>
          ngettext("resta 1 dia, apaga em breve", "restam %{count} dias, apaga em breve", left)

      true ->
        base <> ", " <> ngettext("resta 1 dia", "restam %{count} dias", left)
    end
  end

  defp warning?(item), do: days_left(item) <= @warning_days

  # Cópia de ensino do board, com o mesmo número que o worker usa para
  # expurgar. Função (não assign) porque `@retention_days` no template viria
  # de `assigns`, não do módulo.
  defp retention_line do
    gettext("Os itens ficam %{count} dias na lixeira e depois são apagados de vez.",
      count: @retention_days
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.service flash={@flash} service="ybira" current="lixeira" title={gettext("Documentos")} back={~p"/"}>
      <:actions>
        <.button kind="primary" size="md" class="hide-mobile" navigate={~p"/documentos/enviar?#{[return_to: ~p"/documentos/lixeira"]}"}>
          {gettext("Enviar")}
        </.button>
      </:actions>
      <:fab>
        <.fab label={gettext("Enviar")} navigate={~p"/documentos/enviar?#{[return_to: ~p"/documentos/lixeira"]}"} />
      </:fab>

      <.breadcrumb class="mb-3">
        <:crumb label={gettext("Lixeira")} current />
      </.breadcrumb>

      <p class="type-body-sm text-muted mb-4">{retention_line()}</p>

      <ul :if={@folders != [] or @items != []} class="list">
        <.list_row
          :for={folder <- @folders}
          kind="trash"
          trailing="action"
          title={folder.nome}
          meta={trash_meta(folder)}
          meta_class={warning?(folder) && "text-warning"}
        >
          <:leading>
            <.service_square mark="lixeira" />
          </:leading>
          <:actions>
            <.button
              kind="ghost"
              size="sm"
              phx-click="restore"
              phx-value-id={folder.rkey}
              phx-value-type="folder"
            >
              {gettext("Restaurar")}
            </.button>
          </:actions>
        </.list_row>

        <.list_row
          :for={file <- @items}
          kind="trash"
          trailing="action"
          title={file.nome}
          meta={trash_meta(file)}
          meta_class={warning?(file) && "text-warning"}
        >
          <:leading>
            <.service_square mark="lixeira" />
          </:leading>
          <:actions>
            <.button
              kind="ghost"
              size="sm"
              phx-click="restore"
              phx-value-id={file.rkey}
              phx-value-type="file"
            >
              {gettext("Restaurar")}
            </.button>
          </:actions>
        </.list_row>
      </ul>

      <div :if={@next_cursor} id="trash-load-more" phx-viewport-bottom="load-more" class="list-row" aria-hidden="true">
        <span class="service-square service-square--neutral skeleton"></span>
        <span class="skeleton flex-1" style="height: var(--space-4);"></span>
      </div>

      <.error_card
        :if={@items == [] and @folders == [] and @load_error}
        title={gettext("Não deu para abrir a lixeira")}
        retry_event="retry-load"
      />

      <.empty_state
        :if={@items == [] and @folders == [] and not @load_error}
        icon="trash"
        title={gettext("A lixeira está vazia")}
        body={gettext("Nada foi apagado. O que você apagar aparece aqui por 30 dias antes de sumir de vez.")}
      />
    </Layouts.service>
    """
  end
end
