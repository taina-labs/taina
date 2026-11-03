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
    {:ok,
     socket
     |> assign(:page_title, gettext("Documentos"))
     |> assign(:selection, MapSet.new())
     |> assign(:purge_target, nil)
     |> load_trash()}
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

  def handle_event("toggle-selection", %{"id" => rkey, "type" => type}, socket) when type in ["file", "folder"] do
    if trash_item(socket.assigns, type, rkey) do
      selection = toggle_selection(socket.assigns.selection, {type, rkey})
      {:noreply, assign(socket, :selection, selection)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("clear-selection", _params, socket) do
    {:noreply, assign(socket, :selection, MapSet.new())}
  end

  def handle_event("restore-selected", _params, socket) do
    {restored, failed} =
      apply_trash_selection(socket.assigns.current_scope, selected_trash_items(socket.assigns), :restore)

    {:noreply,
     socket
     |> assign(:selection, MapSet.new())
     |> selection_flash(:restore, restored, failed)
     |> load_trash()}
  end

  def handle_event("ask-purge-selected", _params, socket) do
    items = selected_trash_items(socket.assigns)

    if items == [] do
      {:noreply, socket}
    else
      {:noreply, assign(socket, :purge_target, %{type: "selection", count: length(items), items: items})}
    end
  end

  def handle_event("ask-purge", %{"id" => rkey, "type" => type}, socket) when type in ["file", "folder"] do
    case trash_item(socket.assigns, type, rkey) do
      nil -> {:noreply, put_flash(socket, :error, gettext("Este item não está mais na lixeira."))}
      item -> {:noreply, assign(socket, :purge_target, %{type: type, id: rkey, name: item.nome})}
    end
  end

  def handle_event("close-purge", _params, socket), do: {:noreply, assign(socket, :purge_target, nil)}

  def handle_event("confirm-purge", _params, %{assigns: %{purge_target: %{type: "selection", items: items}}} = socket) do
    {purged, failed} = apply_trash_selection(socket.assigns.current_scope, items, :purge)

    {:noreply,
     socket
     |> assign(:purge_target, nil)
     |> assign(:selection, MapSet.new())
     |> selection_flash(:purge, purged, failed)
     |> load_trash()}
  end

  def handle_event("confirm-purge", _params, %{assigns: %{purge_target: %{type: type, id: rkey}}} = socket) do
    result = purge_item(socket.assigns.current_scope, type, rkey)

    case result do
      {:ok, _item} ->
        {:noreply,
         socket
         |> assign(:purge_target, nil)
         |> deselect_item(type, rkey)
         |> put_flash(:info, gettext("O item foi apagado definitivamente."))
         |> load_trash()}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:purge_target, nil)
         |> put_flash(:error, gettext("Não foi possível apagar o item definitivamente."))}
    end
  end

  def handle_event("confirm-purge", _params, socket), do: {:noreply, socket}

  def handle_event("restore", %{"id" => rkey, "type" => "folder"}, socket) do
    case Ybira.restore_folder(socket.assigns.current_scope, rkey) do
      {:ok, _folder} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Pasta restaurada com o que tinha dentro."))
         |> deselect_item("folder", rkey)
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
         |> deselect_item("file", rkey)
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

  defp trash_item(assigns, "file", rkey), do: Enum.find(assigns.items, &(&1.rkey == rkey))
  defp trash_item(assigns, "folder", rkey), do: Enum.find(assigns.folders, &(&1.rkey == rkey))

  defp selected?(selection, type, rkey), do: MapSet.member?(selection, {type, rkey})

  defp deselect_item(socket, type, rkey) do
    assign(socket, :selection, MapSet.delete(socket.assigns.selection, {type, rkey}))
  end

  defp toggle_selection(selection, item) do
    if MapSet.member?(selection, item), do: MapSet.delete(selection, item), else: MapSet.put(selection, item)
  end

  defp selected_trash_items(assigns) do
    selected_folder_rkeys =
      assigns.selection
      |> Enum.filter(fn {type, _rkey} -> type == "folder" end)
      |> MapSet.new(&elem(&1, 1))

    folders_by_id = Map.new(assigns.folders, &{&1.id, &1})

    assigns.selection
    |> Enum.sort()
    |> Enum.flat_map(&selected_trash_item(assigns, &1, selected_folder_rkeys, folders_by_id))
  end

  defp selected_trash_item(assigns, {type, rkey}, selected_folder_rkeys, folders_by_id) do
    case trash_item(assigns, type, rkey) do
      %Folder{} = folder ->
        if selected_folder_ancestor?(selected_folder_rkeys, folders_by_id, folder.parent_id),
          do: [],
          else: [%{type: type, id: rkey, item: folder}]

      %File{} = file ->
        if selected_folder_ancestor?(selected_folder_rkeys, folders_by_id, file.folder_id),
          do: [],
          else: [%{type: type, id: rkey, item: file}]

      nil ->
        []
    end
  end

  defp selected_folder_ancestor?(_selected_rkeys, _folders_by_id, nil), do: false

  defp selected_folder_ancestor?(selected_rkeys, folders_by_id, folder_id) do
    case Map.get(folders_by_id, folder_id) do
      nil ->
        false

      folder ->
        MapSet.member?(selected_rkeys, folder.rkey) or
          selected_folder_ancestor?(selected_rkeys, folders_by_id, folder.parent_id)
    end
  end

  defp apply_trash_selection(scope, items, action) do
    Enum.reduce(items, {0, 0}, fn %{type: type, id: id}, {succeeded, failed} ->
      if match?({:ok, _}, trash_operation(scope, type, id, action)) do
        {succeeded + 1, failed}
      else
        {succeeded, failed + 1}
      end
    end)
  end

  defp trash_operation(scope, "file", rkey, :restore), do: Ybira.restore_file(scope, rkey)
  defp trash_operation(scope, "folder", rkey, :restore), do: Ybira.restore_folder(scope, rkey)
  defp trash_operation(scope, "file", rkey, :purge), do: Ybira.purge_trash_file(scope, rkey)
  defp trash_operation(scope, "folder", rkey, :purge), do: Ybira.purge_trash_folder(scope, rkey)

  defp selection_flash(socket, _action, 0, 0), do: socket

  defp selection_flash(socket, action, succeeded, 0) do
    message =
      case action do
        :restore ->
          ngettext("1 item restaurado.", "%{count} itens restaurados.", succeeded, count: succeeded)

        :purge ->
          ngettext("1 item apagado definitivamente.", "%{count} itens apagados definitivamente.", succeeded,
            count: succeeded
          )
      end

    put_flash(socket, :info, message)
  end

  defp selection_flash(socket, _action, succeeded, failed) do
    put_flash(
      socket,
      :error,
      gettext("%{done} itens concluídos, %{failed} não puderam ser processados.", done: succeeded, failed: failed)
    )
  end

  defp purge_item(scope, "file", rkey), do: Ybira.purge_trash_file(scope, rkey)
  defp purge_item(scope, "folder", rkey), do: Ybira.purge_trash_folder(scope, rkey)

  defp purge_title(%{type: "file", name: name}), do: gettext("Apagar %{name} de vez?", name: name)
  defp purge_title(%{type: "folder", name: name}), do: gettext("Apagar a pasta %{name} de vez?", name: name)

  defp purge_title(%{type: "selection", count: count}),
    do: ngettext("Apagar 1 item de vez?", "Apagar %{count} itens de vez?", count, count: count)

  defp purge_title(_target), do: nil

  defp purge_body(%{type: "file"}), do: gettext("Este arquivo não poderá ser restaurado.")

  defp purge_body(%{type: "folder"}), do: gettext("A pasta e tudo o que está dentro dela não poderão ser restaurados.")

  defp purge_body(%{type: "selection"}),
    do: gettext("Os itens selecionados não poderão ser restaurados. Pastas apagam também o que está dentro delas.")

  defp purge_body(_target), do: nil

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

      <div :if={MapSet.size(@selection) > 0} id="trash-selection-toolbar" class="selection-toolbar row between mb-4">
        <span class="selection-toolbar__count">{ngettext("1 item selecionado", "%{count} itens selecionados", MapSet.size(@selection))}</span>
        <div class="row gap-2">
          <.button kind="secondary" size="sm" phx-click="restore-selected">{gettext("Restaurar")}</.button>
          <.button kind="danger" size="sm" phx-click="ask-purge-selected">{gettext("Apagar definitivamente")}</.button>
          <.button kind="ghost" size="sm" phx-click="clear-selection">{gettext("Cancelar")}</.button>
        </div>
      </div>

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
            <div class="row gap-2">
              <label class="selection-checkbox__target">
                <input
                  type="checkbox"
                  class="selection-checkbox"
                  checked={selected?(@selection, "folder", folder.rkey)}
                  aria-label={gettext("Selecionar %{name}", name: folder.nome)}
                  phx-click="toggle-selection"
                  phx-value-type="folder"
                  phx-value-id={folder.rkey}
                />
              </label>
              <.service_square mark="lixeira" />
            </div>
          </:leading>
          <:actions>
            <.actions_menu
              id={"trash-folder-#{folder.rkey}"}
              label={gettext("Mais opções para %{name}", name: folder.nome)}
              title={gettext("Ações da pasta")}
            >
              <:item icon="restore" click={JS.push("restore", value: %{id: folder.rkey, type: "folder"})}>
                {gettext("Restaurar")}
              </:item>
              <:item
                icon="trash"
                kind="danger"
                click={JS.push("ask-purge", value: %{id: folder.rkey, type: "folder"})}
              >
                {gettext("Apagar definitivamente")}
              </:item>
            </.actions_menu>
          </:actions>
        </.list_row>

        <.list_row
          :for={file <- @items}
          kind="trash"
          trailing="action"
          title={file.nome}
          meta={trash_meta(file)}
          meta_class={warning?(file) && "text-warning"}
          navigate={~p"/documentos/lixeira/#{file.rkey}"}
        >
          <:leading>
            <div class="row gap-2">
              <label class="selection-checkbox__target">
                <input
                  type="checkbox"
                  class="selection-checkbox"
                  checked={selected?(@selection, "file", file.rkey)}
                  aria-label={gettext("Selecionar %{name}", name: file.nome)}
                  phx-click="toggle-selection"
                  phx-value-type="file"
                  phx-value-id={file.rkey}
                />
              </label>
              <.service_square mark="lixeira" />
            </div>
          </:leading>
          <:actions>
            <.actions_menu
              id={"trash-file-#{file.rkey}"}
              label={gettext("Mais opções para %{name}", name: file.nome)}
              title={gettext("Ações do arquivo")}
            >
              <:item icon="restore" click={JS.push("restore", value: %{id: file.rkey, type: "file"})}>
                {gettext("Restaurar")}
              </:item>
              <:item
                icon="trash"
                kind="danger"
                click={JS.push("ask-purge", value: %{id: file.rkey, type: "file"})}
              >
                {gettext("Apagar definitivamente")}
              </:item>
            </.actions_menu>
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

      <.dialog
        id="confirm-purge"
        show={@purge_target != nil}
        kind="destructive"
        title={purge_title(@purge_target)}
        body={purge_body(@purge_target)}
        confirm_label={gettext("Apagar definitivamente")}
        on_confirm="confirm-purge"
        on_cancel={JS.push("close-purge")}
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
