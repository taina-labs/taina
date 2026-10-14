defmodule TainaWeb.FilesLive do
  @moduledoc """
  Navegador de arquivos do Ybira: pastas + arquivos da pasta atual, breadcrumb
  com a cadeia completa de pastas (Início / ... / pasta atual; em telas
  pequenas o meio encolhe em "..."), ordenação (nome/data/tamanho),
  alternância lista/grade, e ações por item no menu de três pontinhos: abrir,
  renomear, mover (seletor ou arrastar-e-soltar), publicar/tirar da praça e
  excluir (com confirmação). Telas "Ybira - Arquivos" e "Desktop - Arquivos".

  Abrir um item (o corpo da linha ou da grade) navega para a tela dele, com os
  detalhes completos; não há painel lateral, o mesmo caminho no mobile e no
  desktop.

  Ordenação, visão e zona moram na URL (`?sort=name-asc&view=grid&zona=praca`),
  então sobrevivem a navegação, recarga e compartilhamento de link. Paginação
  por offset (`list_folder_contents`), o que permite qualquer ordem.
  """

  use TainaWeb, :live_view

  alias Taina.Ybira
  alias TainaWeb.Layouts

  @impl true
  def handle_params(params, _uri, socket) do
    folder_rkey = params["folder_id"]
    sort = parse_sort(params["sort"])
    view = if params["view"] == "grid", do: :grid, else: :list
    zona = parse_zona(params["zona"])
    scope = socket.assigns.current_scope

    case load_folder(scope, folder_rkey) do
      {:ok, folder} ->
        case Ybira.list_folder_contents(scope, folder_rkey, sort: sort) do
          {:ok, %{folders: folders, files: files, next_cursor: next_cursor}} ->
            zona_folders = for_zona(folders, zona)
            zona_files = for_zona(files, zona)

            {:noreply,
             socket
             |> assign(:page_title, (folder && folder.nome) || gettext("Arquivos"))
             |> assign(:folder, folder)
             |> assign(:breadcrumb, breadcrumb(scope, folder))
             |> assign(:folder_rkey, folder_rkey)
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

      # Casa de outra pessoa: a pasta em si não é para os nossos olhos, volta
      # ao início com o porquê.
      {:error, :forbidden} ->
        {:noreply,
         socket
         |> Phoenix.LiveView.put_flash(
           :error,
           gettext("Esta pasta é particular. Só quem a guardou, e quem essa pessoa deixar, vê.")
         )
         |> Phoenix.LiveView.push_navigate(to: ~p"/arquivos")}
    end
  end

  defp load_folder(_scope, nil), do: {:ok, nil}
  defp load_folder(scope, rkey), do: Ybira.get_folder(scope, rkey)

  # --- breadcrumb (cadeia raiz -> pasta atual) ---

  # A cadeia vem de `Ybira.folder_path/2` (raiz -> atual, inclusive). Se ela
  # falhou por baixo (pasta apagada no meio da requisição, por exemplo), o
  # breadcrumb cai para o elo único de hoje em vez de quebrar a tela.
  defp breadcrumb(_scope, nil), do: []

  defp breadcrumb(scope, folder) do
    case Ybira.folder_path(scope, folder.rkey) do
      {:ok, path} -> path
      {:error, _reason} -> [%{rkey: folder.rkey, nome: folder.nome}]
    end
  end

  # A cadeia inteira vira três papéis: ancestrais como links de patch, a pasta
  # atual sem link e, quando existe meio (ancestrais além do primeiro), um
  # "..." que só aparece em telas pequenas (375px): lá o meio some e ficam
  # sempre o primeiro e o último elo. No desktop a cadeia inteira aparece.
  defp breadcrumb_items([]), do: []

  defp breadcrumb_items([current]), do: [%{kind: :current, nome: current.nome, rkey: current.rkey}]

  defp breadcrumb_items([first | rest]) do
    current = List.last(rest)
    ancestors = [first | Enum.drop(rest, -1)]

    links =
      for {segment, index} <- Enum.with_index(ancestors) do
        %{kind: :link, nome: segment.nome, rkey: segment.rkey, middle?: index > 0}
      end

    ellipsis = if length(ancestors) > 1, do: [%{kind: :ellipsis}], else: []

    links ++ ellipsis ++ [%{kind: :current, nome: current.nome, rkey: current.rkey}]
  end

  @impl true
  def handle_event("load-more", _params, socket) do
    %{next_cursor: offset, folder_rkey: folder_rkey, sort: sort, zona: zona} = socket.assigns

    if offset do
      case Ybira.list_folder_contents(socket.assigns.current_scope, folder_rkey, sort: sort, offset: offset) do
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
    # O seletor so oferece pastas SUAS: mover para pasta alheia o servidor
    # recusa, entao a UI nao pode oferecer.
    case Ybira.list_folders(socket.assigns.current_scope) do
      {:ok, folders} ->
        {:noreply,
         socket
         |> assign(:modal, "move")
         |> assign(:move_target, %{kind: kind, id: id, name: name})
         |> assign(:all_folders, Enum.filter(folders, &own?(socket.assigns.current_scope, &1)))}

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

  # Soltar arquivos do sistema sobre a página: o destino é o upload da pasta
  # atual. O guard de preventDefault mora no hook DnD (JS); sem ele, o
  # navegador navega para fora do app quando o arrasto vem do sistema.
  def handle_event("drop-files", _params, socket) do
    {:noreply, Phoenix.LiveView.push_navigate(socket, to: upload_path(socket.assigns.folder_rkey))}
  end

  def handle_event("create-folder", %{"folder" => %{"name" => name}}, socket) do
    # A pasta nova herda a zona que a pessoa esta vendo: na aba praca, nasce
    # na praca; no default (casa), na casa.
    case Ybira.create_folder(socket.assigns.current_scope, %{
           name: name,
           parent_rkey: socket.assigns.folder_rkey,
           zona: socket.assigns.zona
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
         socket
         |> assign(:modal, nil)
         |> Phoenix.LiveView.put_flash(:error, gettext("Só dá para mover para as suas pastas."))}
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

  # Recarrega a pasta atual reaproveitando o handle_params, preservando
  # ordem/visão/zona e o arquivo aberto no painel de detalhes.
  defp refresh(socket) do
    Phoenix.LiveView.push_patch(socket,
      to:
        browse_path(
          socket.assigns.folder_rkey,
          socket.assigns.sort,
          socket.assigns.view,
          socket.assigns.zona
        )
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

  # No menu de ordenação o item atual ganha um check, e o Nome divide a
  # direção em dois itens (A-Z / Z-A): clicar nunca vira surpresa, aplica
  # exatamente o que está escrito. Data e Tamanho continuam alternando.
  defp sort_check({:name, :asc}, :name_az), do: "check"
  defp sort_check({:name, :desc}, :name_za), do: "check"
  defp sort_check({:date, _}, :date), do: "check"
  defp sort_check({:size, _}, :size), do: "check"
  defp sort_check(_sort, _item), do: nil

  defp browse_path(folder_rkey, sort, view, zona) do
    params = %{sort: sort_param(sort)}
    params = if view == :grid, do: Map.put(params, :view, "grid"), else: params
    # Com o default na casa, quem precisa de marca na URL e a praca.
    params = if zona == :praca, do: Map.put(params, :zona, "praca"), else: params

    case folder_rkey do
      nil -> ~p"/arquivos?#{params}"
      id -> ~p"/arquivos/pasta/#{id}?#{params}"
    end
  end

  # --- zonas casa/praca (RFC_003 D1/D2) ---

  # Particao client-side: a leitura ja trouxe as duas zonas, aqui so escolhemos
  # qual aba mostrar. Conteudo novo nasce na casa, e a listagem acompanha:
  # ausencia do parametro cai em casa, a praca e marcada explicitamente
  # (?zona=praca). Se caisse na praca antes, o upload "sumia" da tela.
  defp parse_zona("praca"), do: :praca
  defp parse_zona(_casa_default), do: :casa

  defp for_zona(items, zona), do: Enum.filter(items, &(&1.zona == zona))

  defp own?(scope, item), do: scope.ava.id == item.dono_id

  # Só pasta SUA é alvo de soltar: o servidor recusa mover para pasta
  # alheia, então a UI não destaca o que não vai funcionar. nil faz o
  # atributo nem chegar ao HTML.
  defp drop_folder(scope, folder) do
    if own?(scope, folder), do: folder.rkey
  end

  # Criar pasta no início é sempre possível; dentro de pasta alheia, o
  # servidor recusa, então o botão nem aparece (não oferecer o que rejeita).
  defp can_create_here?(_scope, nil), do: true
  defp can_create_here?(scope, folder), do: own?(scope, folder)

  defp readability_line(:praca), do: gettext("Todos os moradores veem.")
  defp readability_line(:casa), do: gettext("Só você, e quem você deixar.")

  # A pasta nova herda a zona da aba ativa; o modal diz onde ela nasce antes
  # de nascer.
  defp folder_zone_line(:praca), do: gettext("A pasta nasce na praça. Todos os moradores veem.")
  defp folder_zone_line(:casa), do: gettext("A pasta nasce na sua casa. Só você vê.")

  # O estado vazio diz a verdade sobre onde a pessoa está: na raiz, a aba
  # fala por si; dentro de pasta, a pasta fala. E na casa alheia a cópia
  # para de fingir que a pasta é sua. O segundo argumento é nil na raiz e
  # true/false conforme a pasta é de quem vê.
  defp empty_copy(:praca, nil),
    do: {gettext("A praça está vazia"), gettext("Publique um arquivo ou pasta para começar a memória da comunidade.")}

  defp empty_copy(:praca, _pasta),
    do: {gettext("Nada na praça desta pasta"), gettext("O que esta pasta guardar de comum aparece aqui.")}

  defp empty_copy(:casa, false),
    do: {gettext("Nada seu nesta pasta"), gettext("O que você guardar aqui aparece nesta aba, só para você.")}

  defp empty_copy(:casa, _sua_ou_raiz),
    do: {gettext("Sua casa está vazia"), gettext("Aqui ficam seus arquivos. Só você vê, até deixar alguém entrar.")}

  # Versão curta para as linhas de lista: a linha de meta trunca com
  # reticências, e a zona nunca pode ser a parte que fica de fora.
  defp readability_short(:praca), do: gettext("Todos veem")
  defp readability_short(:casa), do: gettext("Só você")

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
    "#{file_kind(file.mime)}, #{format_bytes(file.tamanho)}"
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
      <div class="row between wrap gap-3 mb-4">
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
            :if={can_create_here?(@current_scope, @folder)}
            name="folder-plus"
            label={gettext("Nova pasta")}
            phx-click="open-modal"
            phx-value-modal="new-folder"
          />
          <.button variant="primary" size="md" navigate={upload_path(@folder_rkey)} class="hide-mobile">
            <.icon name="upload" size={18} /> {gettext("Enviar")}
          </.button>
        </div>
      </div>

      <div class="row between wrap gap-3 mb-4">
        <.segmented>
          <:option patch={browse_path(@folder_rkey, @sort, @view, :praca)} current={@zona == :praca}>
            {gettext("Praça")}
          </:option>
          <:option patch={browse_path(@folder_rkey, @sort, @view, :casa)} current={@zona == :casa}>
            {gettext("Casa")}
          </:option>
        </.segmented>

        <div class="row gap-1">
          <.menu id="sort-menu" icon="sort" label={gettext("Ordenar")}>
            <:item
              icon={sort_check(@sort, :name_az)}
              click={JS.patch(browse_path(@folder_rkey, {:name, :asc}, @view, @zona))}
            >
              {gettext("Nome (A-Z)")}
            </:item>
            <:item
              icon={sort_check(@sort, :name_za)}
              click={JS.patch(browse_path(@folder_rkey, {:name, :desc}, @view, @zona))}
            >
              {gettext("Nome (Z-A)")}
            </:item>
            <:item
              icon={sort_check(@sort, :date)}
              click={JS.patch(browse_path(@folder_rkey, toggle_sort(:date, @sort), @view, @zona))}
            >
              {gettext("Data")}
            </:item>
            <:item
              icon={sort_check(@sort, :size)}
              click={JS.patch(browse_path(@folder_rkey, toggle_sort(:size, @sort), @view, @zona))}
            >
              {gettext("Tamanho")}
            </:item>
          </.menu>
          <span class="type-caption text-muted self-center">
            {sort_label(@sort)} <.icon name={sort_arrow_icon(@sort)} size={14} />
          </span>
          <.icon_button
            name="grid"
            label={gettext("Alternar grade/lista")}
            phx-click={
              JS.patch(
                browse_path(
                  @folder_rkey,
                  @sort,
                  if(@view == :grid, do: :list, else: :grid),
                  @zona
                )
              )
            }
          />
        </div>
      </div>

      <nav class="breadcrumb mb-3" id="ybira-breadcrumb">
        <.link navigate={~p"/arquivos"} class="breadcrumb__link" data-drop-folder="">{gettext("Início")}</.link>
        <%= for item <- breadcrumb_items(@breadcrumb) do %>
          <span class="breadcrumb__sep"><.icon name="chevron-right" size={14} /></span>
          <.link
            :if={item.kind == :link}
            patch={~p"/arquivos/pasta/#{item.rkey}"}
            class={["breadcrumb__link", item.middle? && "hide-mobile"]}
          >
            {item.nome}
          </.link>
          <span :if={item.kind == :ellipsis} class="hide-desktop" aria-hidden="true">...</span>
          <span :if={item.kind == :current} class="breadcrumb__current text-primary">{item.nome}</span>
        <% end %>
      </nav>

      <p class="type-body-sm text-muted mb-3">
        <%= if @next_cursor do %>
          {ngettext("%{count} item carregado", "%{count} itens carregados", @item_count)}
        <% else %>
          {ngettext("%{count} item", "%{count} itens", @item_count)}
        <% end %>
      </p>

      <div id="ybira-dnd" phx-hook="DnD">
        <%= if @view == :grid do %>
          <div class="tiles">
            <div
              :for={folder <- @folders}
              class="tile"
              style="position: relative;"
              data-drop-folder={drop_folder(@current_scope, folder)}
            >
              <.link navigate={~p"/arquivos/pasta/#{folder.rkey}"} class="col gap-1">
                <.service_square service="ybira" icon="folder" size="lg" />
                <p class="tile__title">{folder.nome}</p>
                <p class="tile__meta">{gettext("Pasta")}</p>
                <p class="tile__meta">{readability_line(folder.zona)}</p>
              </.link>
              <div style="position: absolute; top: var(--space-2); right: var(--space-2);">
                <.item_menu
                  kind="folder"
                  id={folder.rkey}
                  name={folder.nome}
                  zona={folder.zona}
                  own?={own?(@current_scope, folder)}
                />
              </div>
            </div>

            <div id="files-grid" phx-update="stream" class="contents">
              <div
                :for={{dom_id, file} <- @streams.files}
                id={dom_id}
                class="tile"
                style="position: relative;"
              >
                <.link navigate={~p"/arquivos/#{file.rkey}"} class="col gap-1">
                  <% {service, icon} = file_visual(file.mime) %>
                  <.service_square service={service} icon={icon} size="lg" />
                  <p class="tile__title">{file.nome}</p>
                  <p class="tile__meta">{file_meta(file)}</p>
                  <p class="tile__meta">{readability_line(file.zona)}</p>
                </.link>
                <div style="position: absolute; top: var(--space-2); right: var(--space-2);">
                  <.item_menu
                    kind="file"
                    id={file.rkey}
                    name={file.nome}
                    zona={file.zona}
                    own?={own?(@current_scope, file)}
                  />
                </div>
              </div>
            </div>
          </div>
        <% else %>
          <div class="list">
            <ul :if={@folders != []} class="list">
              <.list_row
                :for={folder <- @folders}
                title={folder.nome}
                meta={"#{gettext("Pasta")} / #{readability_short(folder.zona)}"}
                navigate={~p"/arquivos/pasta/#{folder.rkey}"}
                draggable="true"
                data-drag-id={folder.rkey}
                data-drag-kind="folder"
                data-drop-folder={drop_folder(@current_scope, folder)}
              >
                <:leading>
                  <.service_square service="ybira" icon="folder" />
                </:leading>
                <:actions>
                  <.item_menu
                    kind="folder"
                    id={folder.rkey}
                    name={folder.nome}
                    zona={folder.zona}
                    own?={own?(@current_scope, folder)}
                  />
                </:actions>
              </.list_row>
            </ul>

            <ul id="files" phx-update="stream" class="list">
              <.list_row
                :for={{dom_id, file} <- @streams.files}
                id={dom_id}
                title={file.nome}
                meta={"#{file_meta(file)} / #{readability_short(file.zona)}"}
                navigate={~p"/arquivos/#{file.rkey}"}
                draggable="true"
                data-drag-id={file.rkey}
                data-drag-kind="file"
              >
                <:leading>
                  <% {service, icon} = file_visual(file.mime) %>
                  <.service_square service={service} icon={icon} />
                </:leading>
                <:actions>
                  <.item_menu
                    kind="file"
                    id={file.rkey}
                    name={file.nome}
                    zona={file.zona}
                    own?={own?(@current_scope, file)}
                  />
                </:actions>
              </.list_row>
            </ul>
          </div>
        <% end %>
      </div>

      <div :if={@next_cursor} id="load-more" phx-viewport-bottom="load-more" class="list-row" aria-hidden="true">
        <span class="service-square service-square--neutral skeleton"></span>
        <span class="skeleton flex-1" style="height: var(--space-4);"></span>
      </div>

      <% {empty_title, empty_hint} = empty_copy(@zona, @folder && own?(@current_scope, @folder)) %>

      <.empty_state :if={@item_count == 0} icon="folder" title={empty_title} hint={empty_hint}>
        <div :if={@zona == :casa and (is_nil(@folder) or own?(@current_scope, @folder))} class="col gap-2">
          <p class="type-body-sm text-muted">
            {gettext("Isso é promessa de software e confiança: o Tainá ainda não criptografa.")}
          </p>
          <.button variant="primary" size="md" navigate={upload_path(@folder_rkey)}>
            {gettext("Enviar arquivos")}
          </.button>
        </div>
      </.empty_state>

      <.button variant="fab" navigate={upload_path(@folder_rkey)} aria-label={gettext("Enviar arquivos")}>
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
          <p class="type-body-sm text-muted">{folder_zone_line(@zona)}</p>
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
        <ul :if={@move_target} class="list">
          <li>
            <button
              type="button"
              class="list-row"
              phx-click={JS.push("move-item", value: %{kind: @move_target.kind, id: @move_target.id, target: ""})}
            >
              <.service_square service="ybira" icon="home" />
              <span class="list-row__body type-label">{gettext("Início (raiz)")}</span>
            </button>
          </li>
          <li :for={folder <- @all_folders} :if={folder.rkey != @move_target.id}>
            <button
              type="button"
              class="list-row"
              phx-click={
                JS.push("move-item", value: %{kind: @move_target.kind, id: @move_target.id, target: folder.rkey})
              }
            >
              <.service_square service="ybira" icon="folder" />
              <span class="list-row__body type-label">{folder.nome}</span>
            </button>
          </li>
        </ul>
        <.button variant="secondary" size="md" class="w-full mt-4" phx-click="close-modal">
          {gettext("Cancelar")}
        </.button>
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
          <p class="type-caption text-muted mt-3">
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
        message={confirm_message(@confirm)}
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

  # Menu de ações compartilhado entre lista e grade. Só o dono renomeia, move,
  # exclui e publica: para quem não é dono, nada daqui funciona no servidor,
  # então o menu nem aparece (a linha continua abrindo pelo link).
  attr :kind, :string, required: true
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :zona, :atom, required: true
  attr :own?, :boolean, required: true

  defp item_menu(assigns) do
    assigns = assign(assigns, :zona_label, elem(zona_action(assigns.zona), 0))

    ~H"""
    <.menu :if={@own?} id={"item-menu-#{@id}"} label={gettext("Mais opções para %{name}", name: @name)}>
      <:item icon="share" click={JS.push("ask-zona", value: %{kind: @kind, id: @id, name: @name, zona: @zona})}>
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

  # A pasta vai para a lixeira com o que tem dentro, mas a restauração é do
  # conteúdo, um a um: a pasta em si não volta (o Ybira não expõe isso ainda).
  # A cópia não promete o que o sistema não faz.
  defp confirm_message(%{kind: "folder"}),
    do: gettext("A pasta e o que tem dentro vão para a lixeira. Os arquivos voltam um a um; a pasta em si, não.")

  defp confirm_message(%{kind: "file"}), do: gettext("Vai para a lixeira. Dá para restaurar em até 30 dias.")
  defp confirm_message(_confirm), do: gettext("Vai para a lixeira.")
end
