defmodule TainaWeb.FilesLive do
  @moduledoc """
  Navegador de Documentos (Ybira): pastas e arquivos da zona corrente. A zona
  é a aba: `/documentos` é a casa e `/documentos/praca` é a praça. Dentro de uma
  pasta, cada item legível aparece sem herdar a zona da pasta. Não há seletor
  de zona na tela e não há badge de zona por linha (a aba inteira já é a zona). Boards
  "Servico / Ybira Praca / padrao" cc1037dc-e8ab-80cc-8008-d5e07c15fbae,
  "pasta" ...d5e1868d4043, "vazio" ...d5e189a70758, "Servico / Ybira Casa /
  padrao" ...d5e18bcb3a18 e "vazio" ...d5e18f3ae917 (mais os quadros "Web 768"
  e "Web", docs/web-revamp-spec.md 6.2).

  As ações de linha moram no `actions_menu` (sheet no mobile, popover no
  desktop): Abrir, Baixar, Publicar na praça / Voltar para a casa, Mover,
  Renomear, Remover. Quais aparecem é função pura do (item, escopo); Remover
  abre o diálogo destrutivo. Pastas aceitam arquivos arrastados
  (`data-drop-folder`, hook DnD) e soltar arquivos do sistema navega ao envio.

  Saíram do navegador antigo o que os boards não mostram: alternância
  lista/grade, menu de ordenação, o seletor Praça/Casa e o mini-modal de
  espaço (o espaço mora no cartão do hub e em /armazenamento).
  """

  use TainaWeb, :live_view

  alias Taina.Maraca
  alias Taina.Ybira
  alias TainaWeb.InternalPath
  alias TainaWeb.Layouts
  alias Ypy.Ybira.File
  alias Ypy.Ybira.Folder

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Documentos"))
     |> assign(:selection, MapSet.new())}
  end

  @impl true
  def handle_params(params, uri, socket) do
    scope = socket.assigns.current_scope
    folder_rkey = params["folder_id"]
    return_to = InternalPath.from_uri(uri)

    case load_folder(scope, folder_rkey) do
      {:ok, folder} ->
        zona = zone_of(socket.assigns.live_action, folder)

        case load_page(scope, folder_rkey, zona) do
          {:ok, page} ->
            {:noreply, assign_page(socket, folder, zona, folder_rkey, page, return_to)}

          {:error, _reason} ->
            {:noreply,
             socket
             |> put_flash(:error, gettext("Não foi possível carregar a pasta."))
             |> push_navigate(to: ~p"/documentos")}
        end

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Pasta não encontrada."))
         |> push_navigate(to: ~p"/documentos")}

      # Casa de outra pessoa: a pasta em si não é para os nossos olhos, volta
      # ao início com o porquê.
      {:error, :forbidden} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           gettext("Esta pasta é particular. Só quem a guardou, e quem essa pessoa deixar, vê.")
         )
         |> push_navigate(to: ~p"/documentos")}
    end
  end

  # A zona é a aba: nas rotas raiz é a live_action; dentro de pasta, a da
  # pasta (spec 6.2).
  defp zone_of(live_action, _folder) when live_action in [:praca, :casa], do: live_action
  defp zone_of(_folder_action, folder), do: folder.zona

  defp load_folder(_scope, nil), do: {:ok, nil}
  defp load_folder(scope, rkey), do: Ybira.get_folder(scope, rkey)

  # Na raiz, a zona filtra no banco antes da paginação. Dentro de uma pasta,
  # cada item legível aparece sem herdar a zona da pasta.
  defp load_page(scope, folder_rkey, zona) do
    with {:ok, %{folders: folders, files: files, next_cursor: next_cursor}} <-
           Ybira.list_folder_contents(scope, folder_rkey, zona: zona),
         {:ok, members} <- Maraca.list_members(scope) do
      {:ok,
       %{
         folders: folders,
         files: files,
         next_cursor: next_cursor,
         names: name_map(members)
       }}
    end
  end

  defp name_map(members), do: Map.new(members, &{&1.id, person_name(&1)})

  # --- casca imperativa: o handle_params só assign/stream ---

  defp assign_page(socket, folder, zona, folder_rkey, page, return_to) do
    breadcrumb =
      case folder do
        nil ->
          []

        %{rkey: rkey} ->
          # A cadeia vem de `Ybira.folder_path/2` (raiz -> atual, inclusive).
          # Se ela falhou por baixo (pasta apagada no meio da requisição, por
          # exemplo), cai para o elo único de hoje em vez de quebrar a tela.
          case Ybira.folder_path(socket.assigns.current_scope, rkey) do
            {:ok, path} -> path
            {:error, _reason} -> [%{rkey: rkey, nome: folder.nome}]
          end
      end

    socket
    |> assign(:page_title, (folder && folder.nome) || gettext("Documentos"))
    |> assign(:folder, folder)
    |> assign(:folder_rkey, folder_rkey)
    |> assign(:zona, zona)
    |> assign(:selection, MapSet.new())
    |> assign(:return_to, return_to)
    |> assign(:breadcrumb, breadcrumb)
    |> assign(:crumbs, crumbs(zona, breadcrumb))
    |> assign(:folders, page.folders)
    |> assign(:folder_counts, folder_counts(socket.assigns.current_scope, page.folders))
    |> assign(:item_count, length(page.folders) + length(page.files))
    |> assign(:file_count, length(page.files))
    |> assign(:next_cursor, page.next_cursor)
    |> assign(:names, page.names)
    |> assign(:modal, nil)
    |> assign(:rename_target, nil)
    |> assign(:move_target, nil)
    |> assign(:all_folders, [])
    |> assign(:confirm, nil)
    |> stream(:files, page.files, reset: true)
  end

  @impl true
  def handle_event("load-more", _params, socket) do
    %{next_cursor: offset, folder_rkey: folder_rkey, zona: zona} = socket.assigns

    if offset do
      case Ybira.list_folder_contents(socket.assigns.current_scope, folder_rkey,
             zona: zona,
             offset: offset
           ) do
        {:ok, %{files: files, next_cursor: next_cursor}} ->
          {:noreply,
           socket
           |> assign(:next_cursor, next_cursor)
           |> assign(:item_count, socket.assigns.item_count + length(files))
           |> assign(:file_count, socket.assigns.file_count + length(files))
           |> stream(:files, files)}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Não foi possível carregar mais itens."))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle-selection", %{"kind" => kind, "id" => id}, socket) when kind in ["file", "folder"] do
    case owned_resource(socket.assigns.current_scope, kind, id) do
      {:ok, _item} ->
        selection = toggle_selection(socket.assigns.selection, {kind, id})
        {:noreply, assign(socket, :selection, selection)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  def handle_event("clear-selection", _params, socket) do
    {:noreply, assign(socket, :selection, MapSet.new())}
  end

  def handle_event("ask-delete-selected", _params, socket) do
    count = MapSet.size(socket.assigns.selection)

    if count == 0 do
      {:noreply, socket}
    else
      {:noreply, assign(socket, :confirm, %{kind: "selection-delete", count: count})}
    end
  end

  def handle_event("open-move-selected", _params, socket) do
    case selected_items(socket.assigns.current_scope, socket.assigns.selection) do
      [] ->
        {:noreply, socket}

      items ->
        case Ybira.list_folders(socket.assigns.current_scope) do
          {:ok, folders} ->
            owned_folders = Enum.filter(folders, &own?(socket.assigns.current_scope, &1))

            {:noreply,
             socket
             |> assign(:modal, "move")
             |> assign(:move_target, %{kind: "selection", id: nil, name: selection_name(length(items))})
             |> assign(:all_folders, owned_folders)}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, gettext("Não foi possível abrir as pastas."))}
        end
    end
  end

  def handle_event("move-selected", %{"target" => target}, socket) do
    target = normalize_target(target)
    {moved, failed} = move_selected_items(socket.assigns.current_scope, socket.assigns.selection, target)

    socket =
      socket
      |> assign(:modal, nil)
      |> assign(:move_target, nil)
      |> assign(:selection, MapSet.new())
      |> selection_flash(:move, moved, failed)

    {:noreply, refresh(socket)}
  end

  def handle_event("confirm-delete-selected", _params, socket) do
    {deleted, failed} = delete_selected_items(socket.assigns.current_scope, socket.assigns.selection)

    socket =
      socket
      |> assign(:confirm, nil)
      |> assign(:selection, MapSet.new())
      |> selection_flash(:delete, deleted, failed)

    {:noreply, refresh(socket)}
  end

  def handle_event("open-modal", %{"modal" => modal}, socket) do
    {:noreply, assign(socket, :modal, modal)}
  end

  def handle_event("open-rename", %{"kind" => kind, "id" => id, "name" => name}, socket) do
    {:noreply, socket |> assign(:modal, "rename") |> assign(:rename_target, %{kind: kind, id: id, name: name})}
  end

  def handle_event("open-move", %{"kind" => kind, "id" => id, "name" => name}, socket) do
    # O seletor só oferece pastas SUAS: mover para pasta alheia o servidor
    # recusa, então a UI não pode oferecer.
    case Ybira.list_folders(socket.assigns.current_scope) do
      {:ok, folders} ->
        {:noreply,
         socket
         |> assign(:modal, "move")
         |> assign(:move_target, %{kind: kind, id: id, name: name})
         |> assign(:all_folders, Enum.filter(folders, &own?(socket.assigns.current_scope, &1)))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Não foi possível abrir as pastas."))}
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
    {:noreply, push_navigate(socket, to: upload_path(socket.assigns.folder_rkey, socket.assigns.return_to))}
  end

  def handle_event("create-folder", %{"folder" => %{"name" => name}}, socket) do
    # A pasta nasce sempre na casa: o kernel não aceita zona na criação
    # (Ybira.create_folder só fala nome e pai). A praça é um passo seguinte,
    # no menu do item; a cópia do modal promete só o que o sistema faz.
    case Ybira.create_folder(socket.assigns.current_scope, %{
           name: name,
           parent_rkey: socket.assigns.folder_rkey
         }) do
      {:ok, _folder} ->
        {:noreply, socket |> put_flash(:info, gettext("Pasta criada.")) |> refresh()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Não foi possível criar a pasta."))}
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
      {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Não foi possível renomear."))}
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
        {:noreply, socket |> put_flash(:info, gettext("Movido.")) |> refresh()}

      {:error, :circular_reference} ->
        {:noreply,
         socket
         |> assign(:modal, nil)
         |> put_flash(:error, gettext("Não dá para mover uma pasta para dentro dela mesma."))}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:modal, nil)
         |> put_flash(:error, gettext("Só dá para mover para as suas pastas."))}
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
         |> put_flash(:info, gettext("Pasta movida para a lixeira."))
         |> refresh()}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:confirm, nil)
         |> put_flash(:error, gettext("Não foi possível remover a pasta."))}
    end
  end

  def handle_event("confirm-delete", _params, %{assigns: %{confirm: %{kind: "file", id: id}}} = socket) do
    case Ybira.delete_file(socket.assigns.current_scope, id) do
      {:ok, _file} ->
        {:noreply,
         socket
         |> assign(:confirm, nil)
         |> put_flash(:info, gettext("Arquivo movido para a lixeira."))
         |> refresh()}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:confirm, nil)
         |> put_flash(:error, gettext("Não foi possível remover o arquivo."))}
    end
  end

  def handle_event("confirm-delete", _params, socket) do
    {:noreply, assign(socket, :confirm, nil)}
  end

  # Publicar arquivo e voltar para casa são ações diretas. Publicar pasta pede
  # confirmação porque também publica todos os itens que estão dentro dela.
  def handle_event("zona", %{"kind" => kind, "id" => id, "action" => action}, socket) do
    if kind == "folder" and action == "publicar" do
      {:noreply, assign(socket, :confirm, %{kind: "publish-folder", id: id})}
    else
      {:noreply, update_zone(socket, kind, action, id)}
    end
  end

  def handle_event("confirm-zone", _params, %{assigns: %{confirm: %{kind: "publish-folder", id: id}}} = socket) do
    socket = assign(socket, :confirm, nil)
    {:noreply, update_zone(socket, "folder", "publicar", id)}
  end

  def handle_event("confirm-zone", _params, socket), do: {:noreply, socket}

  defp update_zone(socket, kind, action, id) do
    scope = socket.assigns.current_scope

    case apply_zona(scope, kind, action, id) do
      {:ok, _} ->
        socket |> put_flash(:info, zona_flash(action, :ok)) |> refresh()

      {:error, _reason} ->
        socket |> put_flash(:error, zona_flash(action, :error)) |> refresh()
    end
  end

  defp apply_zona(scope, "file", "publicar", id), do: Ybira.publicar_file(scope, id)
  defp apply_zona(scope, "file", "voltar", id), do: Ybira.tirar_file_da_praca(scope, id)
  defp apply_zona(scope, "folder", "publicar", id), do: Ybira.publicar_folder(scope, id)
  defp apply_zona(scope, "folder", "voltar", id), do: Ybira.tirar_folder_da_praca(scope, id)

  defp zona_flash("publicar", :ok), do: gettext("Publicado na praça.")
  defp zona_flash("publicar", :error), do: gettext("Não foi possível publicar na praça.")
  defp zona_flash("voltar", :ok), do: gettext("Tirado da praça.")
  defp zona_flash("voltar", :error), do: gettext("Não foi possível tirar da praça.")

  # O shell inscreve o morador nos eventos do Ava; esta tela não reage a eles
  # (a listagem se refaz no próximo handle_params), mas precisa ignorar o que
  # não trata.
  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # Recarrega a pasta atual reaproveitando o handle_params.
  defp refresh(socket) do
    to =
      case socket.assigns.folder_rkey do
        nil -> zone_path(socket.assigns.zona)
        folder_rkey -> ~p"/documentos/pasta/#{folder_rkey}"
      end

    push_patch(socket, to: to)
  end

  # --- core puro: dados -> dados ---

  # "Pasta, 4 itens" (board): o agregado por pasta vem do contexto e vira o
  # meta da linha. Falha do agregado não derruba a listagem: a linha fica só
  # com "Pasta".
  defp folder_counts(scope, folders) do
    case Ybira.folder_item_counts(scope, Enum.map(folders, & &1.id)) do
      {:ok, counts} -> counts
      {:error, _reason} -> %{}
    end
  end

  defp folder_row_meta(folder, counts) do
    case Map.get(counts, folder.id) do
      nil -> gettext("Pasta")
      count -> ngettext("Pasta, %{count} item", "Pasta, %{count} itens", count, count: count)
    end
  end

  # Migalha do desktop (spec 6.2): enraizada na zona ("Praça > Atas"), sem
  # repetir "Início" nem "Documentos" (nota do board "Web / Ybira Casa"). Na
  # raiz da zona, um elo só. No mobile o bloco inteiro some por CSS; quem
  # carrega o parente é a palavra do voltar.
  defp crumbs(zona, []) do
    [%{label: zone_label(zona), current: true}]
  end

  defp crumbs(zona, chain) do
    zone = %{label: zone_label(zona), navigate: zone_path(zona)}

    links =
      for folder <- Enum.drop(chain, -1) do
        %{label: folder.nome, navigate: ~p"/documentos/pasta/#{folder.rkey}"}
      end

    current = chain |> List.last() |> then(&%{label: &1.nome, current: true})

    [zone] ++ links ++ [current]
  end

  defp zone_label(:praca), do: gettext("Praça")
  defp zone_label(:casa), do: gettext("Casa")

  defp zone_path(:praca), do: ~p"/documentos/praca"
  defp zone_path(:casa), do: ~p"/documentos"

  # Voltar da casca: na raiz, o hub ("Início"); dentro de pasta, o parente
  # (a penúltima elo da mesma cadeia da migalha) ou, a um nível do topo, a
  # raiz da própria zona.
  defp shell_back(nil, _breadcrumb, _zona), do: ~p"/"

  defp shell_back(_folder_rkey, breadcrumb, zona) do
    case parent_of(breadcrumb) do
      %{rkey: parent_rkey} -> ~p"/documentos/pasta/#{parent_rkey}"
      _no_parent -> zone_path(zona)
    end
  end

  # A palavra do voltar é o nome do parente (regra 1.5, teto de 12 caracteres
  # em back_label/1); sem parente, a saída padrão da casca ("Início").
  defp shell_back_label(nil, _breadcrumb), do: nil

  defp shell_back_label(_folder_rkey, breadcrumb) do
    case parent_of(breadcrumb) do
      %{nome: nome} -> back_label(nome)
      _no_parent -> nil
    end
  end

  defp parent_of([_current]), do: nil
  defp parent_of(path), do: Enum.at(path, -2)

  defp own?(scope, item), do: scope.ava.id == item.dono_id

  defp owned_resource(scope, "file", rkey) do
    case Ybira.get_file(scope, rkey) do
      {:ok, file} -> if own?(scope, file), do: {:ok, file}, else: {:error, :not_owner}
      {:error, _reason} = error -> error
    end
  end

  defp owned_resource(scope, "folder", rkey) do
    case Ybira.get_folder(scope, rkey) do
      {:ok, folder} -> if own?(scope, folder), do: {:ok, folder}, else: {:error, :not_owner}
      {:error, _reason} = error -> error
    end
  end

  defp selected?(selection, kind, id), do: MapSet.member?(selection, {kind, id})

  # Selection is server state; the key is only meaningful after `owned_resource`
  # has checked the current scope.
  defp toggle_selection(selection, item) do
    if MapSet.member?(selection, item), do: MapSet.delete(selection, item), else: MapSet.put(selection, item)
  end

  defp selected_items(scope, selection) do
    selection
    |> Enum.sort()
    |> Enum.flat_map(fn {kind, id} ->
      case owned_resource(scope, kind, id) do
        {:ok, item} -> [%{kind: kind, id: id, item: item}]
        {:error, _reason} -> []
      end
    end)
  end

  defp selection_name(1), do: gettext("1 item selecionado")
  defp selection_name(count), do: gettext("%{count} itens selecionados", count: count)

  defp move_selected_items(scope, selection, target) do
    apply_selected_items(selection, fn
      "file", id -> Ybira.move_file(scope, id, target)
      "folder", id -> Ybira.move_folder(scope, id, target)
    end)
  end

  defp delete_selected_items(scope, selection) do
    apply_selected_items(selection, fn
      "file", id -> Ybira.delete_file(scope, id)
      "folder", id -> Ybira.delete_folder(scope, id)
    end)
  end

  defp apply_selected_items(selection, operation) do
    selection
    |> Enum.sort()
    |> Enum.reduce({0, 0}, fn {kind, id}, {succeeded, failed} ->
      case operation.(kind, id) do
        {:ok, _item} -> {succeeded + 1, failed}
        {:error, _reason} -> {succeeded, failed + 1}
      end
    end)
  end

  defp selection_flash(socket, _action, 0, 0), do: socket

  defp selection_flash(socket, action, succeeded, 0) do
    message =
      case action do
        :move ->
          ngettext("1 item movido.", "%{count} itens movidos.", succeeded, count: succeeded)

        :delete ->
          ngettext("1 item enviado para a lixeira.", "%{count} itens enviados para a lixeira.", succeeded,
            count: succeeded
          )
      end

    put_flash(socket, :info, message)
  end

  defp selection_flash(socket, action, succeeded, failed) do
    success =
      case action do
        :move ->
          ngettext("1 item movido", "%{count} itens movidos", succeeded, count: succeeded)

        :delete ->
          ngettext("1 item enviado para a lixeira", "%{count} itens enviados para a lixeira", succeeded, count: succeeded)
      end

    put_flash(
      socket,
      :error,
      gettext("%{success}; %{count} não puderam ser concluídos.", success: success, count: failed)
    )
  end

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

  # Quais ações a linha oferece (spec 6.2): função pura do (item, escopo).
  # Só quem é dono publica, move, renomeia e remove; para quem não é, nada
  # daqui funciona no servidor. Pasta não baixa (não há download de pasta).
  defp row_actions(%File{} = file, scope), do: own_actions(file, scope, [:abrir, :baixar])
  defp row_actions(%Folder{} = folder, scope), do: own_actions(folder, scope, [:abrir])

  defp own_actions(item, scope, base) do
    if own?(scope, item) do
      base ++ [zona_action(item.zona), :mover, :renomear, :remover]
    else
      base
    end
  end

  # A ação oferecida é sempre a oposta da zona atual (consentimento, RFC_003).
  defp zona_action(:casa), do: :publicar
  defp zona_action(:praca), do: :voltar

  defp menu_title("file"), do: gettext("Ações do arquivo")
  defp menu_title("folder"), do: gettext("Ações da pasta")

  defp item_path("file", rkey), do: ~p"/documentos/#{rkey}"
  defp item_path("folder", rkey), do: ~p"/documentos/pasta/#{rkey}"

  defp normalize_target(target) when target in [nil, ""], do: nil
  defp normalize_target(target), do: target

  defp move_command(%{kind: "selection"}, target), do: JS.push("move-selected", value: %{target: target || ""})

  defp move_command(%{kind: kind, id: id}, target),
    do: JS.push("move-item", value: %{kind: kind, id: id, target: target || ""})

  defp upload_path(folder_id, return_to) do
    params = [return_to: return_to] ++ if(folder_id, do: [pasta: folder_id], else: [])
    ~p"/documentos/enviar?#{params}"
  end

  # Meta da linha (boards): "PDF, 1,2 MB, só você" na casa; na praça quem
  # enviou, "enviado por Maria" (ou "enviado por você").
  defp file_meta(file, names, ava_id) do
    [base_meta(file), ownership_or_sender(file, names, ava_id)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  defp ownership_or_sender(%{zona: :casa, dono_id: dono_id}, _names, dono_id), do: gettext("só você")
  defp ownership_or_sender(%{dono_id: dono_id}, _names, dono_id), do: gettext("enviado por você")

  defp ownership_or_sender(file, names, _ava_id) do
    case Map.get(names, file.dono_id) do
      nil -> nil
      name -> gettext("enviado por %{name}", name: name)
    end
  end

  defp base_meta(file), do: "#{file_kind(file.mime)}, #{format_bytes(file.tamanho)}"

  # O quadradinho da linha: foto leva o acento do Jaci, vídeo o do vídeo, o
  # resto o documento (o mesmo mapa do hub).
  # "3 arquivos, atualizados ontem" (board pasta): a contagem de arquivos da
  # listagem corrente e o dia relativo da pasta no fuso da comunidade.
  defp folder_meta(file_count, updated_at) do
    ngettext("1 arquivo, atualizado %{when}", "%{count} arquivos, atualizados %{when}", file_count,
      when: relative_time(updated_at)
    )
  end

  # O estado vazio diz a verdade sobre onde a pessoa está (boards "vazio"):
  # na raiz, a zona fala; dentro de pasta, a pasta fala. E na casa alheia a
  # cópia para de fingir que a pasta é sua.
  defp empty_copy(:praca, nil, _scope),
    do:
      {gettext("A praça está vazia"),
       gettext("Quando alguém publicar um arquivo na praça, ele aparece aqui para toda a comunidade.")}

  defp empty_copy(:praca, _folder, _scope),
    do: {gettext("Nada na praça desta pasta"), gettext("O que esta pasta guardar de comum aparece aqui.")}

  defp empty_copy(:casa, nil, _scope),
    do: {gettext("Sua casa está vazia"), gettext("Envie um arquivo. Ele fica só com você até você publicar na praça.")}

  defp empty_copy(:casa, folder, scope) do
    if own?(scope, folder) do
      {gettext("Nada nesta pasta"), gettext("Envie um arquivo. Ele fica só com você até você publicar na praça.")}
    else
      {gettext("Nada para você nesta pasta"), gettext("Só aparece o que a pessoa deixar você ver.")}
    end
  end

  # Diálogo destrutivo (board "Overlay / Dialog remover"): o arquivo vai para
  # a lixeira e some de vez depois de 30 dias; a pasta vai com o que tem
  # dentro e volta como unidade.
  defp confirm_title(%{kind: "publish-folder"}), do: gettext("Publicar pasta e conteúdo na praça?")

  defp confirm_title(%{kind: "selection-delete", count: count}),
    do: ngettext("Remover 1 item?", "Remover %{count} itens?", count, count: count)

  defp confirm_title(%{name: name}), do: gettext("Remover %{name}?", name: name)
  defp confirm_title(_confirm), do: nil

  defp confirm_body(%{kind: "publish-folder"}),
    do: gettext("Os arquivos e as pastas dentro dela também ficarão visíveis para toda a comunidade.")

  defp confirm_body(%{kind: "selection-delete"}),
    do: gettext("Os itens vão para a lixeira. As pastas levam o que está dentro delas.")

  defp confirm_body(%{kind: "file"}), do: gettext("O arquivo vai para a lixeira e some de vez depois de 30 dias.")

  defp confirm_body(%{kind: "folder"}),
    do: gettext("A pasta e o que tem dentro vão para a lixeira e somem de vez depois de 30 dias.")

  defp confirm_body(_confirm), do: nil

  defp confirm_kind(%{kind: "publish-folder"}), do: "confirm"
  defp confirm_kind(_confirm), do: "destructive"

  defp confirm_event(%{kind: "publish-folder"}), do: "confirm-zone"
  defp confirm_event(%{kind: "selection-delete"}), do: "confirm-delete-selected"
  defp confirm_event(_confirm), do: "confirm-delete"

  defp confirm_label(%{kind: "publish-folder"}), do: gettext("Publicar tudo")
  defp confirm_label(_confirm), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.service
      flash={@flash}
      service="ybira"
      current={zone_key(@zona)}
      title={gettext("Documentos")}
      back={shell_back(@folder_rkey, @breadcrumb, @zona)}
      back_label={shell_back_label(@folder_rkey, @breadcrumb)}
    >
      <:actions>
        <div class="row gap-2">
          <.icon_button
            :if={can_create_here?(@current_scope, @folder)}
            name="folder-plus"
            label={gettext("Nova pasta")}
            phx-click="open-modal"
            phx-value-modal="new-folder"
          />
          <.button kind="primary" size="md" class="hide-mobile" navigate={upload_path(@folder_rkey, @return_to)}>
            {gettext("Enviar")}
          </.button>
        </div>
      </:actions>
      <:fab>
        <.fab label={gettext("Enviar")} navigate={upload_path(@folder_rkey, @return_to)} />
      </:fab>

      <.breadcrumb :if={@folder} class="mb-3">
        <:crumb
          :for={crumb <- @crumbs}
          label={crumb.label}
          navigate={crumb[:navigate]}
          current={crumb[:current]}
        />
      </.breadcrumb>

      <% # Linha de contexto da raiz (boards): contagem na praça, ensino na casa.
      %>
      <p
        :if={is_nil(@folder) and @item_count > 0 and @zona == :praca}
        class="type-body-sm text-muted mb-4"
      >
        {ngettext("1 item na praça", "%{count} itens na praça", @item_count)}
      </p>
      <p
        :if={is_nil(@folder) and @item_count > 0 and @zona == :casa}
        class="type-body-sm text-muted mb-4"
      >
        {gettext("Só você vê o que está na casa.")}
      </p>

      <div :if={@folder} class="col gap-1 mb-4">
        <h2 class="type-h2">{@folder.nome}</h2>
        <p class="type-caption text-muted">{folder_meta(@file_count, @folder.updated_at)}</p>
      </div>

      <div :if={MapSet.size(@selection) > 0} id="files-selection-toolbar" class="selection-toolbar row between mb-4">
        <span class="selection-toolbar__count">{selection_name(MapSet.size(@selection))}</span>
        <div class="row gap-2">
          <.button kind="secondary" size="sm" phx-click="open-move-selected">{gettext("Mover")}</.button>
          <.button kind="danger" size="sm" phx-click="ask-delete-selected">{gettext("Remover")}</.button>
          <.button kind="ghost" size="sm" phx-click="clear-selection">{gettext("Cancelar")}</.button>
        </div>
      </div>

      <div id="ybira-dnd" phx-hook="DnD">
        <ul :if={@folders != []} class="list mb-3">
          <.list_row
            :for={folder <- @folders}
            kind="folder"
            trailing="chevron"
            title={folder.nome}
            meta={folder_row_meta(folder, @folder_counts)}
            navigate={item_path("folder", folder.rkey)}
            draggable="true"
            data-drag-id={folder.rkey}
            data-drag-kind="folder"
            data-drop-folder={drop_folder(@current_scope, folder)}
          >
            <:leading>
              <div class="row gap-2">
                <label :if={own?(@current_scope, folder)} class="selection-checkbox__target">
                  <input
                    type="checkbox"
                    class="selection-checkbox"
                    checked={selected?(@selection, "folder", folder.rkey)}
                    aria-label={gettext("Selecionar %{name}", name: folder.nome)}
                    phx-click="toggle-selection"
                    phx-value-kind="folder"
                    phx-value-id={folder.rkey}
                  />
                </label>
                <.service_square mark="ybira" />
              </div>
            </:leading>
            <:actions>
              <.row_menu
                item_kind="folder"
                id={folder.rkey}
                name={folder.nome}
                zona={folder.zona}
                actions={row_actions(folder, @current_scope)}
              />
            </:actions>
          </.list_row>
        </ul>

        <ul id="files" phx-update="stream" class="list">
          <.list_row
            :for={{dom_id, file} <- @streams.files}
            id={dom_id}
            kind="file"
            trailing="kebab"
            title={file.nome}
            meta={file_meta(file, @names, @current_scope.ava.id)}
            navigate={item_path("file", file.rkey)}
            draggable="true"
            data-drag-id={file.rkey}
            data-drag-kind="file"
          >
            <:leading>
              <div class="row gap-2">
                <label :if={own?(@current_scope, file)} class="selection-checkbox__target">
                  <input
                    type="checkbox"
                    class="selection-checkbox"
                    checked={selected?(@selection, "file", file.rkey)}
                    aria-label={gettext("Selecionar %{name}", name: file.nome)}
                    phx-click="toggle-selection"
                    phx-value-kind="file"
                    phx-value-id={file.rkey}
                  />
                </label>
                <.service_square mark={file_mark(file.mime)} />
              </div>
            </:leading>
            <:actions>
              <.row_menu
                item_kind="file"
                id={file.rkey}
                name={file.nome}
                zona={file.zona}
                actions={row_actions(file, @current_scope)}
              />
            </:actions>
          </.list_row>
        </ul>
      </div>

      <div :if={@next_cursor} id="load-more" phx-viewport-bottom="load-more" class="list-row" aria-hidden="true">
        <span class="service-square service-square--neutral skeleton"></span>
        <span class="skeleton flex-1" style="height: var(--space-4);"></span>
      </div>

      <% {empty_title, empty_body} = empty_copy(@zona, @folder, @current_scope) %>

      <.empty_state :if={@item_count == 0} icon="folder" title={empty_title} body={empty_body}>
        <:action :if={@zona == :casa and (is_nil(@folder) or own?(@current_scope, @folder))}>
          <.button kind="primary" size="md" navigate={upload_path(@folder_rkey, @return_to)}>
            {gettext("Enviar um arquivo")}
          </.button>
        </:action>
      </.empty_state>

      <.dialog id="new-folder-modal" show={@modal == "new-folder"} on_cancel={JS.push("close-modal")}>
        <h2 id="new-folder-modal-title" class="type-h3 mb-4">{gettext("Nova pasta")}</h2>
        <form id="create-folder-form" phx-submit="create-folder" class="col gap-4">
          <.field
            label={gettext("Nome da pasta")}
            name="folder[name]"
            id="new_folder_name"
            placeholder={gettext("ex.: Documentos")}
            required
            autofocus
          />
          <p class="type-body-sm text-muted">
            {gettext("A pasta nasce na sua casa. Para todos verem, publique na praça depois.")}
          </p>
          <div class="row gap-3">
            <.button kind="secondary" size="md" class="flex-1" phx-click="close-modal">
              {gettext("Cancelar")}
            </.button>
            <.button type="submit" kind="primary" size="md" class="flex-1">{gettext("Criar")}</.button>
          </div>
        </form>
      </.dialog>

      <.dialog id="rename-modal" show={@modal == "rename"} on_cancel={JS.push("close-modal")}>
        <h2 id="rename-modal-title" class="type-h3 mb-4">{gettext("Renomear")}</h2>
        <form id="rename-form" :if={@rename_target} phx-submit="rename-item" class="col gap-4">
          <.field
            label={gettext("Novo nome")}
            name="folder[name]"
            id="rename_name"
            value={@rename_target.name}
            required
            autofocus
          />
          <div class="row gap-3">
            <.button kind="secondary" size="md" class="flex-1" phx-click="close-modal">
              {gettext("Cancelar")}
            </.button>
            <.button type="submit" kind="primary" size="md" class="flex-1">{gettext("Renomear")}</.button>
          </div>
        </form>
      </.dialog>

      <.dialog id="move-modal" show={@modal == "move"} on_cancel={JS.push("close-modal")}>
        <h2 id="move-modal-title" class="type-h3 mb-1">{gettext("Mover para...")}</h2>
        <p :if={@move_target} class="type-body-sm text-muted mb-4">{@move_target.name}</p>
        <ul :if={@move_target} class="list">
          <li>
            <button
              type="button"
              class="list-row"
              phx-click={move_command(@move_target, nil)}
            >
              <.service_square mark="casa" />
              <span class="list-row__body type-label">{gettext("Início (raiz)")}</span>
            </button>
          </li>
          <li :for={folder <- @all_folders} :if={folder.rkey != @move_target.id}>
            <button
              type="button"
              class="list-row"
              phx-click={move_command(@move_target, folder.rkey)}
            >
              <.service_square mark="ybira" />
              <span class="list-row__body type-label">{folder.nome}</span>
            </button>
          </li>
        </ul>
        <.button kind="secondary" size="md" class="w-full mt-4" phx-click="close-modal">
          {gettext("Cancelar")}
        </.button>
      </.dialog>

      <.dialog
        id="confirm-remove"
        show={@confirm != nil}
        kind={confirm_kind(@confirm)}
        title={confirm_title(@confirm)}
        body={confirm_body(@confirm)}
        confirm_label={confirm_label(@confirm)}
        on_confirm={confirm_event(@confirm)}
        on_cancel={JS.push("close-modal")}
      />
    </Layouts.service>
    """
  end

  # Aba corrente do service_tab_bar: a zona (a aba é a própria rota).
  defp zone_key(:praca), do: "praca"
  defp zone_key(_casa), do: "casa"

  # Menu de ações da linha (actions_menu: sheet no mobile, popover no desktop,
  # spec 4.3). A ordem é a do spec 6.2; quais itens aparecem vem de
  # `row_actions/2`.
  attr :item_kind, :string, required: true
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :zona, :atom, required: true
  attr :actions, :list, required: true

  defp row_menu(assigns) do
    ~H"""
    <.actions_menu
      id={"item-#{@item_kind}-#{@id}"}
      label={gettext("Mais opções para %{name}", name: @name)}
      title={menu_title(@item_kind)}
    >
      <:item :if={:abrir in @actions} icon={@item_kind} navigate={item_path(@item_kind, @id)}>
        {gettext("Abrir")}
      </:item>
      <:item :if={:baixar in @actions} icon="download" href={~p"/files/#{@id}"} download>
        {gettext("Baixar")}
      </:item>
      <:item
        :if={:publicar in @actions}
        icon="share"
        click={JS.push("zona", value: %{kind: @item_kind, id: @id, action: "publicar", name: @name})}
      >
        {if @item_kind == "folder", do: gettext("Publicar pasta e conteúdo na praça"), else: gettext("Publicar na praça")}
      </:item>
      <:item
        :if={:voltar in @actions}
        icon="casa"
        click={JS.push("zona", value: %{kind: @item_kind, id: @id, action: "voltar"})}
      >
        {gettext("Voltar para a casa")}
      </:item>
      <:item
        :if={:mover in @actions}
        icon="move"
        click={JS.push("open-move", value: %{kind: @item_kind, id: @id, name: @name})}
      >
        {gettext("Mover")}
      </:item>
      <:item
        :if={:renomear in @actions}
        icon="pencil"
        click={JS.push("open-rename", value: %{kind: @item_kind, id: @id, name: @name})}
      >
        {gettext("Renomear")}
      </:item>
      <:item
        :if={:remover in @actions}
        icon="trash"
        kind="danger"
        click={JS.push("ask-delete", value: %{kind: @item_kind, id: @id, name: @name})}
      >
        {gettext("Remover")}
      </:item>
    </.actions_menu>
    """
  end
end
