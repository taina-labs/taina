defmodule TainaWeb.FilesLive do
  @moduledoc """
  Navegador de arquivos do Ybira: pastas + arquivos da pasta atual, breadcrumb
  raso (Início / pasta), ordenação (nome/data/tamanho), alternância
  lista/grade, e ações por item: renomear, mover (seletor ou arrastar-e-soltar)
  e excluir (com confirmação). Telas "Ybira - Arquivos" e "Desktop - Arquivos".

  Ordenação e visão moram na URL (`?sort=name-asc&view=grid`), então sobrevivem
  a navegação, recarga e compartilhamento de link. Paginação por offset
  (`list_folder_contents`), o que permite qualquer ordem.
  """

  use TainaWeb, :live_view

  alias Taina.Ybira
  alias TainaWeb.Layouts

  @impl true
  def handle_params(params, _uri, socket) do
    folder_public_id = params["folder_id"]
    sort = parse_sort(params["sort"])
    view = if params["view"] == "grid", do: :grid, else: :list
    zona = parse_zona(params["zona"])
    scope = socket.assigns.current_scope

    case load_folder(scope, folder_public_id) do
      {:ok, folder} ->
        case Ybira.list_folder_contents(scope, folder_public_id, sort: sort) do
          {:ok, %{folders: folders, files: files, next_cursor: next_cursor}} ->
            zona_folders = for_zona(folders, zona)
            zona_files = for_zona(files, zona)

            {:noreply,
             socket
             |> assign(:page_title, (folder && folder.name) || gettext("Arquivos"))
             |> assign(:folder, folder)
             |> assign(:folder_public_id, folder_public_id)
             |> assign(:folders, zona_folders)
             |> assign(:next_cursor, next_cursor)
             |> assign(:item_count, length(zona_folders) + length(zona_files))
             |> assign(:sort, sort)
             |> assign(:view, view)
             |> assign(:zona, zona)
             |> assign(:modal, nil)
             |> assign(:rename_target, nil)
             |> assign(:move_target, nil)
             |> assign(:all_folders, [])
             |> assign(:confirm, nil)
             |> assign(:zona_confirm, nil)
             |> stream(:files, zona_files, reset: true)}

          {:error, _reason} ->
            {:noreply,
             socket
             |> Phoenix.LiveView.put_flash(:error, gettext("Não foi possível carregar a pasta."))
             |> Phoenix.LiveView.push_navigate(to: ~p"/arquivos")}
        end

      {:error, :not_found} ->
        {:noreply,
         socket
         |> Phoenix.LiveView.put_flash(:error, gettext("Pasta não encontrada."))
         |> Phoenix.LiveView.push_navigate(to: ~p"/arquivos")}
    end
  end

  defp load_folder(_scope, nil), do: {:ok, nil}
  defp load_folder(scope, public_id), do: Ybira.get_folder(scope, public_id)

  @impl true
  def handle_event("load-more", _params, socket) do
    %{next_cursor: offset, folder_public_id: folder_public_id, sort: sort, zona: zona} = socket.assigns

    if offset do
      case Ybira.list_folder_contents(socket.assigns.current_scope, folder_public_id, sort: sort, offset: offset) do
        {:ok, %{files: files, next_cursor: next_cursor}} ->
          zona_files = for_zona(files, zona)

          {:noreply,
           socket
           |> assign(:next_cursor, next_cursor)
           |> assign(:item_count, socket.assigns.item_count + length(zona_files))
           |> stream(:files, zona_files)}

        {:error, _reason} ->
          {:noreply, Phoenix.LiveView.put_flash(socket, :error, gettext("Não foi possível carregar mais itens."))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("open-modal", %{"modal" => modal}, socket) do
    {:noreply, assign(socket, :modal, modal)}
  end

  def handle_event("open-rename", %{"kind" => kind, "id" => id, "name" => name}, socket) do
    {:noreply, socket |> assign(:modal, "rename") |> assign(:rename_target, %{kind: kind, id: id, name: name})}
  end

  def handle_event("open-move", %{"kind" => kind, "id" => id, "name" => name}, socket) do
    case Ybira.list_folders(socket.assigns.current_scope) do
      {:ok, folders} ->
        {:noreply,
         socket
         |> assign(:modal, "move")
         |> assign(:move_target, %{kind: kind, id: id, name: name})
         |> assign(:all_folders, folders)}

      {:error, _reason} ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, gettext("Não foi possível abrir as pastas."))}
    end
  end

  def handle_event("close-modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:modal, nil)
     |> assign(:rename_target, nil)
     |> assign(:move_target, nil)
     |> assign(:confirm, nil)}
  end

  def handle_event("create-folder", %{"folder" => %{"name" => name}}, socket) do
    case Ybira.create_folder(socket.assigns.current_scope, %{
           name: name,
           parent_public_id: socket.assigns.folder_public_id
         }) do
      {:ok, _folder} ->
        {:noreply, socket |> Phoenix.LiveView.put_flash(:info, gettext("Pasta criada.")) |> refresh()}

      {:error, _reason} ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, gettext("Não foi possível criar a pasta."))}
    end
  end

  def handle_event("rename-item", %{"folder" => %{"name" => name}}, socket) do
    %{kind: kind, id: id} = socket.assigns.rename_target

    result =
      case kind do
        "folder" -> Ybira.rename_folder(socket.assigns.current_scope, id, name)
        "file" -> Ybira.rename_file(socket.assigns.current_scope, id, name)
        _ -> {:error, :invalid_kind}
      end

    case result do
      {:ok, _} -> {:noreply, refresh(socket)}
      {:error, _} -> {:noreply, Phoenix.LiveView.put_flash(socket, :error, gettext("Não foi possível renomear."))}
    end
  end

  # Mover por seletor (botões do modal) ou por arrastar-e-soltar (hook DnD): os
  # dois caem aqui. `target` vazio = raiz.
  def handle_event("move-item", %{"kind" => kind, "id" => id} = params, socket) do
    target = normalize_target(params["target"])

    result =
      case kind do
        "file" -> Ybira.move_file(socket.assigns.current_scope, id, target)
        "folder" -> Ybira.move_folder(socket.assigns.current_scope, id, target)
        _ -> {:error, :invalid_kind}
      end

    case result do
      {:ok, _} ->
        {:noreply, socket |> Phoenix.LiveView.put_flash(:info, gettext("Movido.")) |> refresh()}

      {:error, :circular_reference} ->
        {:noreply,
         socket
         |> assign(:modal, nil)
         |> Phoenix.LiveView.put_flash(:error, gettext("Não dá para mover uma pasta para dentro dela mesma."))}

      {:error, _} ->
        {:noreply,
         socket |> assign(:modal, nil) |> Phoenix.LiveView.put_flash(:error, gettext("Não foi possível mover."))}
    end
  end

  def handle_event("ask-delete", %{"kind" => kind, "id" => id, "name" => name}, socket) do
    {:noreply, assign(socket, :confirm, %{kind: kind, id: id, name: name})}
  end

  def handle_event("confirm-delete", _params, %{assigns: %{confirm: %{kind: "folder", id: id}}} = socket) do
    case Ybira.delete_folder(socket.assigns.current_scope, id) do
      {:ok, :deleted} ->
        {:noreply,
         socket
         |> assign(:confirm, nil)
         |> Phoenix.LiveView.put_flash(:info, gettext("Pasta movida para a lixeira."))
         |> refresh()}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:confirm, nil)
         |> Phoenix.LiveView.put_flash(:error, gettext("Não foi possível excluir a pasta."))}
    end
  end

  def handle_event("confirm-delete", _params, %{assigns: %{confirm: %{kind: "file", id: id}}} = socket) do
    case Ybira.delete_file(socket.assigns.current_scope, id) do
      {:ok, _file} ->
        {:noreply,
         socket
         |> assign(:confirm, nil)
         |> Phoenix.LiveView.put_flash(:info, gettext("Arquivo movido para a lixeira."))
         |> refresh()}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:confirm, nil)
         |> Phoenix.LiveView.put_flash(:error, gettext("Não foi possível excluir o arquivo."))}
    end
  end

  def handle_event("confirm-delete", _params, socket) do
    {:noreply, assign(socket, :confirm, nil)}
  end

  # `zona` aqui e a zona ATUAL do item: a acao oferecida e sempre a oposta.
  def handle_event("ask-zona", %{"kind" => kind, "id" => id, "name" => name, "zona" => zona}, socket) do
    {:noreply, assign(socket, :zona_confirm, %{kind: kind, id: id, name: name, zona: parse_zona(zona)})}
  end

  def handle_event("close-zona", _params, socket) do
    {:noreply, assign(socket, :zona_confirm, nil)}
  end

  def handle_event("confirm-zona", _params, %{assigns: %{zona_confirm: %{kind: kind, id: id, zona: zona}}} = socket) do
    scope = socket.assigns.current_scope

    result =
      case {kind, zona} do
        {"file", :casa} -> Ybira.publicar_file(scope, id)
        {"file", :praca} -> Ybira.tirar_file_da_praca(scope, id)
        {"folder", :casa} -> Ybira.publicar_folder(scope, id)
        {"folder", :praca} -> Ybira.tirar_folder_da_praca(scope, id)
        _ -> {:error, :invalid_kind}
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:zona_confirm, nil)
         |> Phoenix.LiveView.put_flash(:info, zona_flash_ok(zona))
         |> refresh()}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:zona_confirm, nil)
         |> Phoenix.LiveView.put_flash(:error, zona_flash_error(zona))}
    end
  end

  def handle_event("confirm-zona", _params, socket) do
    {:noreply, assign(socket, :zona_confirm, nil)}
  end

  # Recarrega a pasta atual reaproveitando o handle_params, preservando ordem/visão/zona.
  defp refresh(socket) do
    Phoenix.LiveView.push_patch(socket,
      to: browse_path(socket.assigns.folder_public_id, socket.assigns.sort, socket.assigns.view, socket.assigns.zona)
    )
  end

  # --- ordenação / visão / caminhos ---

  defp parse_sort("name-asc"), do: {:name, :asc}
  defp parse_sort("name-desc"), do: {:name, :desc}
  defp parse_sort("date-asc"), do: {:date, :asc}
  defp parse_sort("size-asc"), do: {:size, :asc}
  defp parse_sort("size-desc"), do: {:size, :desc}
  defp parse_sort(_default), do: {:date, :desc}

  defp sort_param({field, dir}), do: "#{field}-#{dir}"

  # Clicar no campo já ativo inverte a direção; em outro campo, começa crescente.
  defp toggle_sort(field, {field, :asc}), do: {field, :desc}
  defp toggle_sort(field, {field, :desc}), do: {field, :asc}
  defp toggle_sort(field, _other), do: {field, :asc}

  defp sort_label({:name, _}), do: gettext("Nome")
  defp sort_label({:date, _}), do: gettext("Data")
  defp sort_label({:size, _}), do: gettext("Tamanho")

  defp sort_arrow_icon({_field, :asc}), do: "chevron-up"
  defp sort_arrow_icon({_field, :desc}), do: "chevron-down"

  defp browse_path(folder_public_id, sort, view, zona) do
    params = %{sort: sort_param(sort)}
    params = if view == :grid, do: Map.put(params, :view, "grid"), else: params
    params = if zona == :casa, do: Map.put(params, :zona, "casa"), else: params

    case folder_public_id do
      nil -> ~p"/arquivos?#{params}"
      id -> ~p"/arquivos/pasta/#{id}?#{params}"
    end
  end

  # --- zonas casa/praca (RFC_003 D1/D2) ---

  # Particao client-side: a leitura ja trouxe as duas zonas, aqui so escolhemos
  # qual aba mostrar. Ausencia do parametro cai em praca (commons por padrao).
  defp parse_zona("casa"), do: :casa
  defp parse_zona(_default), do: :praca

  defp for_zona(items, zona), do: Enum.filter(items, &(&1.zona == zona))

  defp own?(scope, item), do: scope.ava.id == item.ava_id

  defp readability_line(:praca), do: gettext("Todos os moradores veem.")
  defp readability_line(:casa), do: gettext("Só você, e quem você deixar.")

  defp zona_action(:casa), do: {gettext("Publicar na praça"), "publicar"}
  defp zona_action(:praca), do: {gettext("Tirar da praça"), "tirar-da-praca"}

  defp zona_flash_ok(:casa), do: gettext("Publicado na praça.")
  defp zona_flash_ok(:praca), do: gettext("Tirado da praça.")

  defp zona_flash_error(:casa), do: gettext("Não foi possível publicar na praça.")
  defp zona_flash_error(:praca), do: gettext("Não foi possível tirar da praça.")

  defp normalize_target(target) when target in [nil, ""], do: nil
  defp normalize_target(target), do: target

  defp upload_path(nil), do: ~p"/arquivos/enviar"
  defp upload_path(folder_id), do: ~p"/arquivos/enviar?#{[pasta: folder_id]}"

  defp file_meta(file) do
    "#{file_kind(file.mime_type)}, #{format_bytes(file.file_size_bytes)}"
  end

  defp storage_percent(%{used_bytes: used, quota_bytes: quota}) when is_integer(quota) and quota > 0 do
    round(used / quota * 100)
  end

  defp storage_percent(_stats), do: 0

  defp storage_free(%{used_bytes: used, quota_bytes: quota}) when is_integer(quota), do: max(quota - used, 0)
  defp storage_free(_stats), do: 0

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active_tab={:files}
      storage_stats={assigns[:storage_stats]}
      account_alert={assigns[:account_alert] || false}
    >
      <div class="row between mb-2">
        <h1 class="type-h1">{gettext("Arquivos")}</h1>
        <div class="row gap-2">
          <.icon_button
            name="info"
            label={gettext("Espaço da comunidade")}
            phx-click="open-modal"
            phx-value-modal="storage-info"
          />
          <.icon_button name="trash" label={gettext("Lixeira")} navigate={~p"/arquivos/lixeira"} />
          <.icon_button
            name="folder-plus"
            label={gettext("Nova pasta")}
            phx-click="open-modal"
            phx-value-modal="new-folder"
          />
          <.button variant="primary" size="md" navigate={upload_path(@folder_public_id)} class="hide-mobile">
            <.icon name="upload" size={18} /> {gettext("Enviar")}
          </.button>
        </div>
      </div>

      <div class="row between mb-3">
        <.menu id="sort-menu" icon="list" label={gettext("Ordenar")}>
          <:item click={JS.patch(browse_path(@folder_public_id, toggle_sort(:name, @sort), @view, @zona))}>
            {gettext("Nome")}
          </:item>
          <:item click={JS.patch(browse_path(@folder_public_id, toggle_sort(:date, @sort), @view, @zona))}>
            {gettext("Data")}
          </:item>
          <:item click={JS.patch(browse_path(@folder_public_id, toggle_sort(:size, @sort), @view, @zona))}>
            {gettext("Tamanho")}
          </:item>
        </.menu>

        <div class="row gap-2">
          <span class="type-caption text-muted self-center">
            {sort_label(@sort)} <.icon name={sort_arrow_icon(@sort)} size={14} />
          </span>
          <.icon_button
            name="grid"
            label={gettext("Alternar grade/lista")}
            phx-click={
              JS.patch(browse_path(@folder_public_id, @sort, if(@view == :grid, do: :list, else: :grid), @zona))
            }
          />
        </div>
      </div>

      <.segmented>
        <:option patch={browse_path(@folder_public_id, @sort, @view, :praca)} current={@zona == :praca}>
          {gettext("Praça")}
        </:option>
        <:option patch={browse_path(@folder_public_id, @sort, @view, :casa)} current={@zona == :casa}>
          {gettext("Casa")}
        </:option>
      </.segmented>

      <nav class="breadcrumb mb-4" id="ybira-breadcrumb">
        <.link navigate={~p"/arquivos"} data-drop-folder="">{gettext("Início")}</.link>
        <span :if={@folder} class="breadcrumb__sep"><.icon name="chevron-right" size={14} /></span>
        <span :if={@folder} class="text-primary">{@folder.name}</span>
      </nav>

      <p class="type-body-sm text-muted mb-3">
        {ngettext("%{count} item", "%{count} itens", @item_count)}
      </p>

      <div id="ybira-dnd" phx-hook="DnD">
        <%= if @view == :grid do %>
          <div class="tiles">
            <.link
              :for={folder <- @folders}
              navigate={~p"/arquivos/pasta/#{folder.public_id}"}
              class="tile"
              data-drop-folder={folder.public_id}
            >
              <.service_square service="ybira" icon="folder" size="lg" />
              <p class="tile__title">{folder.name}</p>
              <p class="tile__meta">{gettext("Pasta")}</p>
              <p class="tile__meta">{readability_line(folder.zona)}</p>
            </.link>

            <div id="files-grid" phx-update="stream" class="contents">
              <.link
                :for={{dom_id, file} <- @streams.files}
                id={dom_id}
                navigate={~p"/arquivos/#{file.public_id}"}
                class="tile"
              >
                <% {service, icon} = file_visual(file.mime_type) %>
                <.service_square service={service} icon={icon} size="lg" />
                <p class="tile__title">{file.original_filename}</p>
                <p class="tile__meta">{file_meta(file)}</p>
                <p class="tile__meta">{readability_line(file.zona)}</p>
              </.link>
            </div>
          </div>
        <% else %>
          <div class="list">
            <.list_row
              :for={folder <- @folders}
              title={folder.name}
              meta={"#{gettext("Pasta")} / #{readability_line(folder.zona)}"}
              navigate={~p"/arquivos/pasta/#{folder.public_id}"}
              draggable="true"
              data-drag-id={folder.public_id}
              data-drag-kind="folder"
              data-drop-folder={folder.public_id}
            >
              <:leading>
                <.service_square service="ybira" icon="folder" />
              </:leading>
              <:actions>
                <.item_menu
                  kind="folder"
                  id={folder.public_id}
                  name={folder.name}
                  zona={folder.zona}
                  own?={own?(@current_scope, folder)}
                />
              </:actions>
            </.list_row>

            <div id="files" phx-update="stream">
              <.list_row
                :for={{dom_id, file} <- @streams.files}
                id={dom_id}
                title={file.original_filename}
                meta={"#{file_meta(file)} / #{readability_line(file.zona)}"}
                navigate={~p"/arquivos/#{file.public_id}"}
                draggable="true"
                data-drag-id={file.public_id}
                data-drag-kind="file"
              >
                <:leading>
                  <% {service, icon} = file_visual(file.mime_type) %>
                  <.service_square service={service} icon={icon} />
                </:leading>
                <:actions>
                  <.item_menu
                    kind="file"
                    id={file.public_id}
                    name={file.original_filename}
                    zona={file.zona}
                    own?={own?(@current_scope, file)}
                  />
                </:actions>
              </.list_row>
            </div>
          </div>
        <% end %>
      </div>

      <div :if={@next_cursor} id="load-more" phx-viewport-bottom="load-more" class="center py-4">
        <p class="type-caption text-faint">{gettext("Carregando mais...")}</p>
      </div>

      <.empty_state
        :if={@item_count == 0 and @zona == :praca}
        icon="folder"
        title={gettext("A praça está vazia")}
        hint={gettext("Publique um arquivo ou pasta para começar a memória da comunidade.")}
      />

      <.empty_state
        :if={@item_count == 0 and @zona == :casa}
        icon="folder"
        title={gettext("Sua casa está vazia")}
        hint={gettext("Aqui ficam seus arquivos. Só você vê, até deixar alguém entrar.")}
      >
        <.button variant="primary" size="md" navigate={upload_path(@folder_public_id)}>
          {gettext("Enviar arquivos")}
        </.button>
      </.empty_state>

      <.button variant="fab" navigate={upload_path(@folder_public_id)} aria-label={gettext("Enviar arquivos")}>
        <.icon name="plus" />
      </.button>

      <.modal id="new-folder-modal" show={@modal == "new-folder"} on_cancel={JS.push("close-modal")}>
        <h2 class="type-h3 mb-4">{gettext("Nova pasta")}</h2>
        <form id="create-folder-form" phx-submit="create-folder" class="col gap-4">
          <.input
            label={gettext("Nome da pasta")}
            name="folder[name]"
            id="new_folder_name"
            value=""
            placeholder={gettext("ex.: Documentos")}
            required
            autofocus
          />
          <div class="row gap-3">
            <.button variant="secondary" size="md" class="flex-1" phx-click="close-modal">
              {gettext("Cancelar")}
            </.button>
            <.button type="submit" variant="primary" size="md" class="flex-1">{gettext("Criar")}</.button>
          </div>
        </form>
      </.modal>

      <.modal id="rename-modal" show={@modal == "rename"} on_cancel={JS.push("close-modal")}>
        <h2 class="type-h3 mb-4">{gettext("Renomear")}</h2>
        <form id="rename-form" :if={@rename_target} phx-submit="rename-item" class="col gap-4">
          <.input
            label={gettext("Novo nome")}
            name="folder[name]"
            id="rename_name"
            value={@rename_target.name}
            required
            autofocus
          />
          <div class="row gap-3">
            <.button variant="secondary" size="md" class="flex-1" phx-click="close-modal">
              {gettext("Cancelar")}
            </.button>
            <.button type="submit" variant="primary" size="md" class="flex-1">{gettext("Renomear")}</.button>
          </div>
        </form>
      </.modal>

      <.modal id="move-modal" show={@modal == "move"} on_cancel={JS.push("close-modal")}>
        <h2 class="type-h3 mb-1">{gettext("Mover para...")}</h2>
        <p :if={@move_target} class="type-body-sm text-muted mb-4">{@move_target.name}</p>
        <div :if={@move_target} class="list">
          <button
            type="button"
            class="list-row"
            phx-click={JS.push("move-item", value: %{kind: @move_target.kind, id: @move_target.id, target: ""})}
          >
            <.service_square service="ybira" icon="home" />
            <span class="list-row__body type-label">{gettext("Início (raiz)")}</span>
          </button>
          <button
            :for={folder <- @all_folders}
            :if={folder.public_id != @move_target.id}
            type="button"
            class="list-row"
            phx-click={
              JS.push("move-item", value: %{kind: @move_target.kind, id: @move_target.id, target: folder.public_id})
            }
          >
            <.service_square service="ybira" icon="folder" />
            <span class="list-row__body type-label">{folder.name}</span>
          </button>
        </div>
      </.modal>

      <.modal id="storage-info-modal" show={@modal == "storage-info"} on_cancel={JS.push("close-modal")}>
        <h2 class="type-h3 mb-1">{gettext("Espaço da comunidade")}</h2>
        <p class="type-body-sm text-muted mb-4">
          {gettext("Tudo o que vocês enviam divide o mesmo espaço. É da comunidade inteira.")}
        </p>

        <%= if @storage_stats do %>
          <.progress value={storage_percent(@storage_stats)} />
          <div class="row between mt-2">
            <span class="type-body-sm text-muted">
              {gettext("%{used} de %{total} usados",
                used: format_bytes(@storage_stats.used_bytes),
                total: format_bytes(@storage_stats.quota_bytes)
              )}
            </span>
            <span class="type-body-sm text-success">
              {gettext("%{free} livres", free: format_bytes(storage_free(@storage_stats)))}
            </span>
          </div>
          <p class="type-caption text-faint mt-3">
            {gettext("Quando o espaço acabar, quem cuida da comunidade pode aumentar o limite.")}
          </p>
          <.button variant="secondary" size="md" navigate={~p"/armazenamento"} class="w-full mt-4">
            {gettext("Ver detalhes")}
          </.button>
        <% else %>
          <p class="type-body-sm text-muted">{gettext("Não foi possível carregar o uso agora.")}</p>
        <% end %>
      </.modal>

      <.confirm_dialog
        id="confirm-delete"
        show={@confirm != nil}
        title={confirm_title(@confirm)}
        message={gettext("Vai para a lixeira. Dá para restaurar em até 30 dias.")}
        on_confirm="confirm-delete"
        on_cancel={JS.push("close-modal")}
      />

      <.modal id="confirm-zona" show={@zona_confirm != nil} on_cancel={JS.push("close-zona")}>
        <div :if={@zona_confirm}>
          <h2 class="type-h3 mb-2">{zona_confirm_title(@zona_confirm)}</h2>
          <p class="type-body text-secondary mb-2">{zona_confirm_body(@zona_confirm.zona)}</p>
          <p :if={@zona_confirm.kind == "folder" and @zona_confirm.zona == :casa} class="type-body text-secondary mb-6">
            {gettext("Só a pasta entra na praça. Os arquivos dentro dela continuam como estão.")}
          </p>
          <div class="row gap-3">
            <.button variant="secondary" size="md" class="flex-1" phx-click="close-zona">
              {gettext("Cancelar")}
            </.button>
            <.button variant="primary" size="md" class="flex-1" phx-click="confirm-zona">
              {zona_confirm_primary(@zona_confirm.zona)}
            </.button>
          </div>
        </div>
      </.modal>
    </Layouts.app>
    """
  end

  # Texto do dialogo: a zona guardada e a ATUAL; a copia descreve a acao oposta.
  defp zona_confirm_title(%{zona: :casa, name: name}), do: gettext("Publicar \"%{name}\" na praça?", name: name)
  defp zona_confirm_title(%{zona: :praca, name: name}), do: gettext("Tirar \"%{name}\" da praça?", name: name)

  defp zona_confirm_body(:casa), do: gettext("Todos os moradores vão poder ver. Você pode tirar da praça quando quiser.")

  defp zona_confirm_body(:praca), do: gettext("Volta a ser só seu. Só você, e quem você deixar, vê de novo.")

  defp zona_confirm_primary(:casa), do: gettext("Publicar")
  defp zona_confirm_primary(:praca), do: gettext("Tirar da praça")

  # Menu de ações compartilhado entre lista e grade.
  attr :kind, :string, required: true
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :zona, :atom, required: true
  attr :own?, :boolean, required: true

  defp item_menu(assigns) do
    assigns = assign(assigns, :zona_label, elem(zona_action(assigns.zona), 0))

    ~H"""
    <.menu id={"item-menu-#{@id}"} label={gettext("Mais opções")}>
      <:item
        :if={@own?}
        icon="share"
        click={JS.push("ask-zona", value: %{kind: @kind, id: @id, name: @name, zona: @zona})}
      >
        {@zona_label}
      </:item>
      <:item icon="pencil" click={JS.push("open-rename", value: %{kind: @kind, id: @id, name: @name})}>
        {gettext("Renomear")}
      </:item>
      <:item icon="move" click={JS.push("open-move", value: %{kind: @kind, id: @id, name: @name})}>
        {gettext("Mover")}
      </:item>
      <:item icon="trash" danger click={JS.push("ask-delete", value: %{kind: @kind, id: @id, name: @name})}>
        {gettext("Excluir")}
      </:item>
    </.menu>
    """
  end

  defp confirm_title(%{kind: "folder", name: name}), do: gettext("Excluir a pasta \"%{name}\"?", name: name)
  defp confirm_title(%{kind: "file", name: name}), do: gettext("Excluir \"%{name}\"?", name: name)
  defp confirm_title(_confirm), do: gettext("Excluir?")
end
