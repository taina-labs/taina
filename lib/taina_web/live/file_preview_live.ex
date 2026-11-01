defmodule TainaWeb.FilePreviewLive do
  @moduledoc """
  Detalhe/preview de um arquivo (boards "Servico / Ybira Arquivo / padrao"
  cc1037dc-e8ab-80cc-8008-d5e21a59286b e "casa alheia" ...d5e21d8161ac): tela
  empurrada, sem abas. Título é o nome do arquivo; o voltar devolve para a
  pasta onde ele mora, com o nome dela na palavra. No corpo: a mídia inline
  (imagem/vídeo/áudio/PDF via `/files/:id`, que já fala `Range`), o badge de
  zona, quem enviou, quando e onde, e as ações Baixar / Remover (o destructive
  dialog do board "Overlay / Dialog remover"). As ações do menu (publicar /
  voltar para a casa, remover) são função pura do (arquivo, escopo).

  Casa de outra pessoa: o nome do arquivo não vaza para quem não pode lê lo
  (o board intitula a tela "Documento", genérico); a saída é pedir acesso.
  """

  use TainaWeb, :live_view

  alias Taina.Maraca
  alias Taina.Ybira
  alias TainaWeb.Layouts
  alias TainaWeb.Time

  @impl true
  def mount(%{"id" => rkey}, _session, socket) do
    scope = socket.assigns.current_scope

    case Ybira.get_file(scope, rkey) do
      {:ok, file} ->
        {back, back_label, folder_name} = back_target(scope, file)

        {:ok,
         socket
         |> assign(:page_title, gettext("Documentos"))
         |> assign(:file, file)
         |> assign(:back, back)
         |> assign(:back_label, back_label)
         |> assign(:folder_name, folder_name)
         |> assign(:names, load_names(scope))
         |> assign(:photo_metadata, load_photo_metadata(scope, file))
         |> assign(:text_preview, load_text_preview(file))
         |> assign(:modal, nil)
         |> assign(:all_folders, [])
         |> assign(:show_confirm, false)}

      {:error, :forbidden} ->
        {:ok, mount_forbidden(socket, rkey)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Arquivo não encontrado."))
         |> redirect(to: ~p"/documentos/casa")}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Não foi possível abrir o arquivo agora."))
         |> redirect(to: ~p"/documentos/casa")}
    end
  end

  # O voltar devolve para a pasta onde o arquivo mora, com o nome dela na
  # palavra (regra 1.5); arquivo da raiz (ou pasta que não se pode ver) volta
  # para o início da zona do arquivo.
  defp back_target(scope, file) do
    case Ybira.file_folder_rkey(scope, file) do
      {:ok, folder_rkey} ->
        case Ybira.get_folder(scope, folder_rkey) do
          {:ok, folder} ->
            {~p"/documentos/pasta/#{folder.rkey}", back_label(folder.nome), folder.nome}

          _error ->
            root_target(file.zona)
        end

      _no_folder ->
        root_target(file.zona)
    end
  end

  defp root_target(:praca), do: {~p"/documentos", gettext("Praça"), nil}
  defp root_target(:casa), do: {~p"/documentos/casa", gettext("Casa"), nil}

  # Casa de outra pessoa: a pessoa não lê o conteúdo, mas vê o caminho (o
  # pedido de acesso). O nome do dono fica para o contexto validar; a tela
  # não nomeia nem o arquivo.
  defp mount_forbidden(socket, rkey) do
    case Ybira.fetch_access_target(socket.assigns.current_scope, rkey) do
      {:ok, target} ->
        socket
        |> assign(:page_title, gettext("Documento"))
        |> assign(:access_target, target)

      {:error, :already_readable} ->
        push_navigate(socket, to: ~p"/documentos/#{rkey}")

      {:error, :not_found} ->
        socket
        |> put_flash(:error, gettext("Arquivo não encontrado."))
        |> redirect(to: ~p"/documentos/casa")
    end
  end

  defp load_names(scope) do
    case Maraca.list_members(scope) do
      {:ok, members} -> Map.new(members, &{&1.id, person_name(&1)})
      _error -> %{}
    end
  end

  # As rendições (dimensões, EXIF, thumbnails) moram nos metadados do produto;
  # o arquivo do kernel só carrega o conteúdo.
  defp load_photo_metadata(scope, file) do
    {:ok, metadata} = Ybira.photo_metadata(scope, file)
    metadata
  end

  # Pré-visualização de texto: lê até 256 KB do disco (o suficiente para a tela;
  # arquivos maiores mostram o começo). Falha de leitura: sem preview, cai no
  # quadradinho do arquivo.
  @text_preview_limit 256 * 1024

  defp load_text_preview(%{mime: "text/" <> _} = file) do
    with {:ok, path} <- Ybira.blob_path(file),
         {:ok, device} <- File.open(path, [:read, :binary, :raw]) do
      try do
        case :file.read(device, @text_preview_limit) do
          {:ok, content} when is_binary(content) -> content
          _ -> nil
        end
      after
        :file.close(device)
      end
    else
      _ -> nil
    end
  end

  defp load_text_preview(_file), do: nil

  @impl true
  def handle_event("ask-delete", _params, socket) do
    {:noreply, assign(socket, :show_confirm, true)}
  end

  def handle_event("close-confirm", _params, socket) do
    {:noreply, assign(socket, :show_confirm, false)}
  end

  def handle_event("open-rename", _params, socket), do: {:noreply, assign(socket, :modal, "rename")}

  def handle_event("rename-file", %{"file" => %{"name" => name}}, socket) do
    case Ybira.rename_file(socket.assigns.current_scope, socket.assigns.file.rkey, name) do
      {:ok, file} ->
        {:noreply,
         socket
         |> assign_file(file)
         |> assign(:modal, nil)
         |> put_flash(:info, gettext("Renomeado."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Não foi possível renomear."))}
    end
  end

  def handle_event("open-move", _params, socket) do
    case Ybira.list_folders(socket.assigns.current_scope) do
      {:ok, folders} ->
        own_folders = Enum.filter(folders, &(&1.dono_id == socket.assigns.current_scope.ava.id))
        {:noreply, socket |> assign(:modal, "move") |> assign(:all_folders, own_folders)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Não foi possível abrir as pastas."))}
    end
  end

  def handle_event("move-file", %{"target" => target}, socket) do
    folder_rkey = if target == "", do: nil, else: target

    case Ybira.move_file(socket.assigns.current_scope, socket.assigns.file.rkey, folder_rkey) do
      {:ok, file} ->
        {:noreply,
         socket
         |> assign_file(file)
         |> assign(:modal, nil)
         |> put_flash(:info, gettext("Movido."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Não foi possível mover."))}
    end
  end

  def handle_event("close-modal", _params, socket), do: {:noreply, assign(socket, :modal, nil)}

  def handle_event("confirm-delete", _params, socket) do
    case Ybira.delete_file(socket.assigns.current_scope, socket.assigns.file.rkey) do
      {:ok, _file} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Arquivo movido para a lixeira."))
         |> push_navigate(to: ~p"/documentos/casa")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Não foi possível remover o arquivo."))}
    end
  end

  # Publicar / Voltar direto do menu (o consentimento é reversível, RFC_003;
  # os boards não têm diálogo de confirmação para a zona, só para remover).
  def handle_event("zona", %{"action" => action}, socket) do
    %{file: file, current_scope: scope} = socket.assigns

    result =
      case action do
        "publicar" -> Ybira.publicar_file(scope, file.rkey)
        "voltar" -> Ybira.tirar_file_da_praca(scope, file.rkey)
      end

    case result do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign_file(updated)
         |> put_flash(:info, zona_flash(action, :ok))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, zona_flash(action, :error))}
    end
  end

  # O pedido vai sem motivo: a tela não tem campo para a pessoa escrever, e
  # motivo fabricado por servidor ("pedido pela tela do arquivo") parece
  # coisa que ninguém disse. Quem quiser explicar, explica na aprovação.
  def handle_event("request-access", _params, socket) do
    target = socket.assigns.access_target
    scope = socket.assigns.current_scope

    case Maraca.pedir_acesso(scope, "ypy.file.v0", target.rkey, nil) do
      {:ok, _request} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Pedido enviado. Você vê o andamento em Pedidos."))
         |> push_navigate(to: ~p"/conta/pedidos")}

      {:error, :already_has_access} ->
        {:noreply, push_navigate(socket, to: ~p"/documentos/#{target.rkey}")}

      {:error, :cannot_request_own} ->
        {:noreply, push_navigate(socket, to: ~p"/documentos/#{target.rkey}")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Não foi possível enviar o pedido agora."))}
    end
  end

  defp assign_file(socket, file) do
    {back, back_label, folder_name} = back_target(socket.assigns.current_scope, file)

    socket
    |> assign(:file, file)
    |> assign(:back, back)
    |> assign(:back_label, back_label)
    |> assign(:folder_name, folder_name)
  end

  # O shell inscreve o morador nos eventos do Ava; esta tela não reage a eles,
  # mas precisa ignorar o que não trata.
  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # --- core puro: dados -> dados ---

  defp own?(scope, file), do: scope.ava.id == file.dono_id

  # "Enviado por": você quando é seu; o nome de quem enviou quando não é.
  defp sender_name(%{dono_id: dono_id}, _names, dono_id), do: gettext("você")

  defp sender_name(file, names, _ava_id) do
    Map.get(names, file.dono_id) || ""
  end

  # "Hoje, 14:32" (board): o dia no fuso da comunidade, com a hora do relógio
  # local; mais velho que ontem, a data por inteiro (o banco grava em UTC,
  # exibir hora em UTC seria mentir).
  defp sent_line(%{inserted_at: at}) do
    days = Date.diff(Time.local_today(), Time.local_date(at))
    clock = Time.local_clock(at)

    cond do
      days <= 0 -> gettext("Hoje") <> ", " <> clock
      days == 1 -> gettext("Ontem") <> ", " <> clock
      true -> Calendar.strftime(Time.local_date(at), "%d/%m/%Y") <> ", " <> clock
    end
  end

  # "Praça, pasta Atas" (board): a zona e a pasta onde mora; na raiz, a zona.
  defp where_line(zona, nil), do: zone_word(zona)
  defp where_line(zona, folder_name), do: zone_word(zona) <> ", " <> gettext("pasta %{name}", name: folder_name)

  defp zone_word(:praca), do: gettext("Praça")
  defp zone_word(:casa), do: gettext("Casa")

  defp badge_kind(:praca), do: "praca"
  defp badge_kind(:casa), do: "casa"

  defp media_kind("image/" <> _rest), do: :image
  defp media_kind("video/" <> _rest), do: :video
  defp media_kind("audio/" <> _rest), do: :audio
  defp media_kind("application/pdf"), do: :pdf
  defp media_kind("text/" <> _rest), do: :text
  defp media_kind(_mime), do: :other

  # Dimensões intrínsecas para o <img> (metadata da Rendition): o layout não
  # pula enquanto a imagem carrega. Vídeo não tem metadata equivalente hoje.
  defp file_dimension(metadata, "width") do
    case metadata do
      %{"width" => w, "height" => _h} -> w
      _ -> nil
    end
  end

  defp file_dimension(metadata, "height") do
    case metadata do
      %{"width" => _w, "height" => h} -> h
      _ -> nil
    end
  end

  defp base_meta(file), do: "#{file_kind(file.mime)}, #{format_bytes(file.tamanho)}"

  defp zona_flash("publicar", :ok), do: gettext("Publicado na praça.")
  defp zona_flash("publicar", :error), do: gettext("Não foi possível publicar na praça.")
  defp zona_flash("voltar", :ok), do: gettext("Tirado da praça.")
  defp zona_flash("voltar", :error), do: gettext("Não foi possível tirar da praça.")

  @impl true
  def render(%{access_target: _target} = assigns) do
    ~H"""
    <Layouts.page flash={@flash} title={@page_title} back={~p"/"}>
      <div class="col gap-4 mx-auto w-full measure">
        <.empty_state
          icon="shield"
          title={gettext("Esta casa é particular")}
          body={gettext("Este arquivo está na casa de outra pessoa. Só quem guardou pode liberar.")}
        >
          <:action>
            <.button kind="primary" phx-click="request-access">{gettext("Pedir acesso")}</.button>
          </:action>
        </.empty_state>
      </div>
    </Layouts.page>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.page flash={@flash} title={@page_title} back={@back} back_label={@back_label}>
      <:action>
        <.icon_button name="download" label={gettext("Baixar")} href={~p"/files/#{@file.rkey}"} download />
        <.preview_menu file={@file} scope={@current_scope} />
      </:action>

      <div class="col gap-4 mx-auto w-full measure">
        <div class="surface-raised radius-lg center media-frame col gap-2">
          <%= case media_kind(@file.mime) do %>
            <% :image -> %>
              <img
                src={~p"/files/#{@file.rkey}"}
                alt={@file.nome}
                width={file_dimension(@photo_metadata, "width")}
                height={file_dimension(@photo_metadata, "height")}
              />
            <% :video -> %>
              <video controls playsinline src={~p"/files/#{@file.rkey}"} class="w-full"></video>
            <% :audio -> %>
              <audio controls src={~p"/files/#{@file.rkey}"} class="w-full p-4"></audio>
            <% :pdf -> %>
              <iframe
                src={~p"/files/#{@file.rkey}"}
                title={@file.nome}
                class="w-full doc-frame"
              >
              </iframe>
            <% :text -> %>
              <pre :if={@text_preview} class="text-preview">{@text_preview}</pre>
              <.service_square :if={!@text_preview} mark="doc" size="lg" />
            <% :other -> %>
              <.service_square mark="doc" size="lg" />
          <% end %>

          <h2 class="type-h3">{@file.nome}</h2>
          <div class="row items-center gap-2">
            <span class="type-caption text-muted">{base_meta(@file)}</span>
            <.badge kind={badge_kind(@file.zona)}>{zone_word_lower(@file.zona)}</.badge>
          </div>
        </div>

        <div class="col gap-3">
          <div>
            <p class="type-caption text-muted">{gettext("Enviado por")}</p>
            <p class="type-body">{sender_name(@file, @names, @current_scope.ava.id)}</p>
          </div>
          <div>
            <p class="type-caption text-muted">{gettext("Quando")}</p>
            <p class="type-body">{sent_line(@file)}</p>
          </div>
          <div>
            <p class="type-caption text-muted">{gettext("Onde")}</p>
            <p class="type-body">{where_line(@file.zona, @folder_name)}</p>
          </div>
        </div>

        <div class="row gap-3">
          <.button kind="secondary" size="md" class="flex-1" href={~p"/files/#{@file.rkey}"} download>
            {gettext("Baixar")}
          </.button>
          <.button
            :if={own?(@current_scope, @file)}
            kind="danger"
            size="md"
            class="flex-1"
            phx-click="ask-delete"
          >
            {gettext("Remover")}
          </.button>
        </div>
      </div>

      <.dialog
        id="confirm-remove"
        show={@show_confirm}
        kind="destructive"
        title={gettext("Remover %{name}?", name: @file.nome)}
        body={gettext("O arquivo vai para a lixeira e some de vez depois de 30 dias.")}
        on_confirm="confirm-delete"
        on_cancel={JS.push("close-confirm")}
      />

      <.dialog id="rename-file-modal" show={@modal == "rename"} on_cancel={JS.push("close-modal")}>
        <h2 id="rename-file-modal-title" class="type-h3 mb-4">{gettext("Renomear")}</h2>
        <form id="rename-file-form" phx-submit="rename-file" class="col gap-4">
          <.field label={gettext("Novo nome")} name="file[name]" id="rename_file_name" value={@file.nome} required autofocus />
          <div class="row gap-3">
            <.button kind="secondary" size="md" class="flex-1" phx-click="close-modal">
              {gettext("Cancelar")}
            </.button>
            <.button type="submit" kind="primary" size="md" class="flex-1">{gettext("Renomear")}</.button>
          </div>
        </form>
      </.dialog>

      <.dialog id="move-file-modal" show={@modal == "move"} on_cancel={JS.push("close-modal")}>
        <h2 id="move-file-modal-title" class="type-h3 mb-1">{gettext("Mover para...")}</h2>
        <p class="type-body-sm text-muted mb-4">{@file.nome}</p>
        <ul class="list">
          <li>
            <button type="button" class="list-row" phx-click={JS.push("move-file", value: %{target: ""})}>
              <.service_square mark="casa" />
              <span class="list-row__body type-label">{gettext("Início (raiz)")}</span>
            </button>
          </li>
          <li :for={folder <- @all_folders} :if={folder.id != @file.folder_id}>
            <button
              type="button"
              class="list-row"
              phx-click={JS.push("move-file", value: %{target: folder.rkey})}
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
    </Layouts.page>
    """
  end

  # A palavra da zona no badge (board W: "praça"), minúscula.
  defp zone_word_lower(:praca), do: gettext("praça")
  defp zone_word_lower(:casa), do: gettext("casa")

  # Ações do arquivo aberto (spec 6.2: cabeçalho com Baixar + actions_menu).
  # Sem "Abrir" (o arquivo já está aberto); publicar e remover são do dono, e
  # a ação de zona é sempre a oposta (consentimento, RFC_003).
  attr :file, :any, required: true
  attr :scope, :any, required: true

  defp preview_menu(assigns) do
    assigns = assign(assigns, :own?, own?(assigns.scope, assigns.file))

    ~H"""
    <.actions_menu
      id="file-actions"
      label={gettext("Mais opções para %{name}", name: @file.nome)}
      title={gettext("Ações do arquivo")}
    >
      <:item icon="download" navigate={~p"/files/#{@file.rkey}"}>{gettext("Baixar")}</:item>
      <:item
        :if={@own? and @file.zona == :casa}
        icon="share"
        click={JS.push("zona", value: %{action: "publicar"})}
      >
        {gettext("Publicar na praça")}
      </:item>
      <:item
        :if={@own? and @file.zona == :praca}
        icon="casa"
        click={JS.push("zona", value: %{action: "voltar"})}
      >
        {gettext("Voltar para a casa")}
      </:item>
      <:item :if={@own?} icon="move" click={JS.push("open-move")}>
        {gettext("Mover")}
      </:item>
      <:item :if={@own?} icon="pencil" click={JS.push("open-rename")}>
        {gettext("Renomear")}
      </:item>
      <:item :if={@own?} icon="trash" kind="danger" click={JS.push("ask-delete")}>
        {gettext("Remover")}
      </:item>
    </.actions_menu>
    """
  end
end
