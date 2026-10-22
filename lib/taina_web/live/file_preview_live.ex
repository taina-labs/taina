defmodule TainaWeb.FilePreviewLive do
  @moduledoc """
  Detalhe/preview de um arquivo (tela "Ybira - Preview"): mídia inline
  (imagem/vídeo/áudio/PDF via `/files/:id`, que já fala `Range`), metadados e
  ações: baixar, copiar link, detalhes, excluir (lixeira).
  """

  use TainaWeb, :live_view

  alias Taina.Maraca
  alias Taina.Ybira
  alias TainaWeb.Layouts

  @impl true
  def mount(%{"id" => rkey}, _session, socket) do
    case Ybira.get_file(socket.assigns.current_scope, rkey) do
      {:ok, file} ->
        # O voltar devolve para a pasta onde o arquivo mora, não para o início;
        # arquivo da raiz (ou pasta que não se pode ver) volta para o início.
        back = back_path(Ybira.file_folder_rkey(socket.assigns.current_scope, file))

        {:ok,
         socket
         |> assign(:page_title, file.nome)
         |> assign(:file, file)
         |> assign(:back, back)
         |> assign(:photo_metadata, load_photo_metadata(socket.assigns.current_scope, file))
         |> assign(:text_preview, load_text_preview(file))
         |> assign(:show_details, false)
         |> assign(:show_confirm, false)
         |> assign(:show_zona, false)}

      {:error, :forbidden} ->
        {:ok, mount_forbidden(socket, rkey)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> Phoenix.LiveView.put_flash(:error, gettext("Arquivo não encontrado."))
         |> Phoenix.LiveView.redirect(to: ~p"/arquivos")}

      {:error, _reason} ->
        {:ok,
         socket
         |> Phoenix.LiveView.put_flash(:error, gettext("Não foi possível abrir o arquivo agora."))
         |> Phoenix.LiveView.redirect(to: ~p"/arquivos")}
    end
  end

  # Casa de outra pessoa: a pessoa nao le o conteudo, mas vemos a quem pedir.
  defp mount_forbidden(socket, rkey) do
    case Ybira.fetch_access_target(socket.assigns.current_scope, rkey) do
      {:ok, target} ->
        socket
        |> assign(:page_title, gettext("Pedir acesso"))
        |> assign(:access_target, target)
        |> assign(:show_request_modal, false)

      {:error, :already_readable} ->
        Phoenix.LiveView.push_navigate(socket, to: ~p"/arquivos/#{rkey}")

      {:error, :not_found} ->
        socket
        |> Phoenix.LiveView.put_flash(:error, gettext("Arquivo não encontrado."))
        |> Phoenix.LiveView.redirect(to: ~p"/arquivos")
    end
  end

  # As rendições (dimensões, EXIF, thumbnails) moram nos metadados do produto;
  # o arquivo do kernel só carrega o conteúdo.
  defp load_photo_metadata(scope, file) do
    {:ok, metadata} = Ybira.photo_metadata(scope, file)
    metadata
  end

  # Resultado do `Ybira.file_folder_rkey/2` vira caminho do voltar: pasta
  # visível, volta para ela; qualquer outro caso, volta para o início.
  defp back_path({:ok, folder_rkey}), do: ~p"/arquivos/pasta/#{folder_rkey}"
  defp back_path(_other), do: ~p"/arquivos"

  @impl true
  def handle_event("copied", _params, socket) do
    {:noreply, Phoenix.LiveView.put_flash(socket, :info, gettext("Link copiado!"))}
  end

  # A guarda de clipboard fica no hook (JS); quando ele não consegue copiar
  # (origem insegura, sem permissão), a saída é o campo do link no cartão:
  # selecionar e copiar por conta própria.
  def handle_event("copy-failed", _params, socket) do
    {:noreply,
     Phoenix.LiveView.put_flash(
       socket,
       :error,
       gettext("Não deu para copiar agora. Toque no campo do link, selecione e copie.")
     )}
  end

  def handle_event("toggle-details", _params, socket) do
    {:noreply, assign(socket, :show_details, !socket.assigns.show_details)}
  end

  def handle_event("ask-delete", _params, socket) do
    {:noreply, assign(socket, :show_confirm, true)}
  end

  def handle_event("close-confirm", _params, socket) do
    {:noreply, assign(socket, :show_confirm, false)}
  end

  def handle_event("confirm-delete", _params, socket) do
    case Ybira.delete_file(socket.assigns.current_scope, socket.assigns.file.rkey) do
      {:ok, _file} ->
        {:noreply,
         socket
         |> Phoenix.LiveView.put_flash(:info, gettext("Arquivo movido para a lixeira."))
         |> Phoenix.LiveView.push_navigate(to: ~p"/arquivos")}

      {:error, _reason} ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, gettext("Não foi possível excluir o arquivo."))}
    end
  end

  def handle_event("ask-zona", _params, socket) do
    {:noreply, assign(socket, :show_zona, true)}
  end

  def handle_event("close-zona", _params, socket) do
    {:noreply, assign(socket, :show_zona, false)}
  end

  def handle_event("confirm-zona", _params, socket) do
    %{file: file, current_scope: scope} = socket.assigns

    result =
      case file.zona do
        :casa -> Ybira.publicar_file(scope, file.rkey)
        :praca -> Ybira.tirar_file_da_praca(scope, file.rkey)
      end

    case result do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:file, updated)
         |> assign(:show_zona, false)
         |> Phoenix.LiveView.put_flash(:info, zona_flash_ok(file.zona))}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:show_zona, false)
         |> Phoenix.LiveView.put_flash(:error, zona_flash_error(file.zona))}
    end
  end

  def handle_event("ask-access", _params, socket) do
    {:noreply, assign(socket, :show_request_modal, true)}
  end

  def handle_event("close-access", _params, socket) do
    {:noreply, assign(socket, :show_request_modal, false)}
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
         |> Phoenix.LiveView.put_flash(:info, gettext("Pedido enviado. Você vê o andamento em Pedidos."))
         |> Phoenix.LiveView.push_navigate(to: ~p"/conta/pedidos")}

      {:error, :already_has_access} ->
        {:noreply, Phoenix.LiveView.push_navigate(socket, to: ~p"/arquivos/#{target.rkey}")}

      {:error, :cannot_request_own} ->
        {:noreply, Phoenix.LiveView.push_navigate(socket, to: ~p"/arquivos/#{target.rkey}")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:show_request_modal, false)
         |> Phoenix.LiveView.put_flash(:error, gettext("Não foi possível enviar o pedido agora."))}
    end
  end

  defp own?(scope, file), do: scope.ava.id == file.dono_id

  # O nome do dono para gente: o display quando existe, o username como
  # reserva (a mesma regra das telas de pedidos). O fetch_access_target ja
  # o trouxe; pedir acesso e pedir a uma pessoa, nao a um arquivo solto.
  defp owner_name(%{owner: %{display_name: display_name, username: username}}) do
    display_name || username
  end

  defp readability_line(:praca), do: gettext("Todos os moradores veem.")
  defp readability_line(:casa), do: gettext("Só você, e quem você deixar.")

  defp zona_action_label(:casa), do: gettext("Publicar")
  defp zona_action_label(:praca), do: gettext("Tirar da praça")

  defp zona_confirm_title(:casa, name), do: gettext("Publicar \"%{name}\" na praça?", name: name)
  defp zona_confirm_title(:praca, name), do: gettext("Tirar \"%{name}\" da praça?", name: name)

  defp zona_confirm_body(:casa), do: gettext("Todos os moradores vão poder ver. Você pode tirar da praça quando quiser.")

  defp zona_confirm_body(:praca), do: gettext("Volta a ser só seu. Só você, e quem você deixar, vê de novo.")

  defp zona_confirm_primary(:casa), do: gettext("Publicar")
  defp zona_confirm_primary(:praca), do: gettext("Tirar da praça")

  defp zona_flash_ok(:casa), do: gettext("Publicado na praça.")
  defp zona_flash_ok(:praca), do: gettext("Tirado da praça.")

  defp zona_flash_error(:casa), do: gettext("Não foi possível publicar na praça.")
  defp zona_flash_error(:praca), do: gettext("Não foi possível tirar da praça.")

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

  # `inserted_at` é UTC e não sabemos o fuso de quem lê; exibir a hora em UTC
  # seria mentir, então a tela mostra só a data.
  defp sent_date(%{inserted_at: at}), do: Calendar.strftime(at, "%d/%m/%Y")

  # Pré-visualização de texto: lê até 256 KB do disco (o suficiente para a tela;
  # arquivos maiores mostram o começo). Falha de leitura: sem preview, cai no
  # ícone genérico.
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

  defp file_meta(file, metadata) do
    dimensions =
      case metadata do
        %{"width" => w, "height" => h} -> ", #{w}x#{h}"
        _ -> ""
      end

    "#{file_kind(file.mime)}, #{format_bytes(file.tamanho)}#{dimensions}, " <>
      gettext("enviado %{when}", when: relative_time(file.inserted_at))
  end

  @impl true
  def render(%{access_target: _target} = assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active_tab={:files}
      storage_stats={assigns[:storage_stats]}
      account_alert={assigns[:account_alert] || false}
    >
      <Layouts.app_bar title={gettext("Pedir acesso")} back={~p"/arquivos"} />

      <div class="col gap-4 mx-auto w-full measure">
        <.empty_state
          icon="shield"
          title={gettext("Esta casa é particular")}
          hint={
            gettext(
              "O arquivo é de %{name}. Para abrir, peça acesso e a pessoa decide. O Tainá ainda não criptografa: é promessa de software, não cadeado.",
              name: owner_name(@access_target)
            )
          }
        >
          <.button variant="primary" phx-click="ask-access">{gettext("Pedir acesso")}</.button>
        </.empty_state>
      </div>

      <.modal id="request-access" show={@show_request_modal} on_cancel={JS.push("close-access")}>
        <h2 class="type-h3 mb-2">
          {gettext("Pedir acesso a %{name}?", name: owner_name(@access_target))}
        </h2>
        <p class="type-body text-secondary mb-6">
          {gettext("%{name} recebe seu pedido sobre \"%{file}\" e decide se deixa você ver.",
            name: owner_name(@access_target),
            file: @access_target.nome
          )}
        </p>
        <div class="row gap-3">
          <.button variant="secondary" size="md" class="flex-1" phx-click="close-access">
            {gettext("Cancelar")}
          </.button>
          <.button variant="primary" size="md" class="flex-1" phx-click="request-access">
            {gettext("Pedir acesso")}
          </.button>
        </div>
      </.modal>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active_tab={:files}
      storage_stats={assigns[:storage_stats]}
      account_alert={assigns[:account_alert] || false}
    >
      <Layouts.app_bar title={@file.nome} back={@back}>
        <:action>
          <.icon_button name="download" label={gettext("Baixar")} href={~p"/files/#{@file.rkey}"} download />
        </:action>
      </Layouts.app_bar>

      <div class="col gap-4 mx-auto w-full measure-wide">
        <div class="surface-raised radius-lg center media-frame">
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
              <.empty_state
                :if={!@text_preview}
                icon="file"
                title={gettext("Pré-visualização indisponível")}
                hint={gettext("O arquivo está intacto; baixe para ler por inteiro.")}
              >
                <.button variant="secondary" href={~p"/files/#{@file.rkey}"} download>
                  {gettext("Baixar")}
                </.button>
              </.empty_state>
            <% :other -> %>
              <.empty_state
                icon="file"
                title={gettext("Pré-visualização indisponível")}
                hint={gettext("O arquivo está intacto; baixe para abrir no seu dispositivo.")}
              >
                <.button variant="secondary" href={~p"/files/#{@file.rkey}"} download>
                  {gettext("Baixar")}
                </.button>
              </.empty_state>
          <% end %>
        </div>

        <.card>
          <h2 class="type-h3 mb-1">{@file.nome}</h2>
          <p class="type-body-sm text-muted">{file_meta(@file, @photo_metadata)}</p>
          <p class="type-body-sm text-muted">{readability_line(@file.zona)}</p>
          <% file_url = url(~p"/arquivos/#{@file.rkey}") %>
          <div class="field mt-4">
            <label for="file-page-link">{gettext("Link do arquivo")}</label>
            <div class="field__control">
              <input id="file-page-link" type="text" value={file_url} readonly />
            </div>
          </div>
          <hr class="divider my-4" />
          <div class="row between wrap">
            <button
              type="button"
              class="viewer__action"
              id="copy-file-link"
              phx-hook="Clipboard"
              data-copy={file_url}
            >
              <.icon name="link" size={20} />
              <span>{gettext("Link")}</span>
            </button>
            <button
              :if={own?(@current_scope, @file)}
              type="button"
              class="viewer__action"
              phx-click="ask-zona"
            >
              <.icon name="share" size={20} />
              <span>{zona_action_label(@file.zona)}</span>
            </button>
            <button
              :if={own?(@current_scope, @file)}
              type="button"
              class="viewer__action viewer__action--danger"
              phx-click="ask-delete"
            >
              <.icon name="trash" size={20} />
              <span>{gettext("Excluir")}</span>
            </button>
            <button type="button" class="viewer__action" phx-click="toggle-details">
              <.icon name="info" size={20} />
              <span>{gettext("Detalhes")}</span>
            </button>
          </div>
        </.card>
      </div>

      <.modal id="file-details" show={@show_details} on_cancel={JS.push("toggle-details")}>
        <h2 class="type-h3 mb-4">{gettext("Detalhes")}</h2>
        <div class="col gap-3">
          <div>
            <p class="type-caption text-muted">{gettext("Nome original")}</p>
            <p class="type-body">{@file.nome}</p>
          </div>
          <div>
            <p class="type-caption text-muted">{gettext("Tipo")}</p>
            <p class="type-body">{file_kind(@file.mime)}</p>
            <p class="type-mono-sm text-muted">{@file.mime}</p>
          </div>
          <div>
            <p class="type-caption text-muted">{gettext("Tamanho")}</p>
            <p class="type-body">{format_bytes(@file.tamanho)}</p>
          </div>
          <div>
            <p class="type-caption text-muted">{gettext("Assinatura do arquivo")}</p>
            <p class="type-mono-sm truncate">{@file.hash}</p>
            <p class="type-caption text-muted">{gettext("É como o Tainá confere que o arquivo está intacto.")}</p>
          </div>
          <div>
            <p class="type-caption text-muted">{gettext("Enviado em")}</p>
            <p class="type-body">{sent_date(@file)}</p>
          </div>
        </div>
        <.button variant="secondary" class="w-full mt-6" phx-click="toggle-details">
          {gettext("Fechar")}
        </.button>
      </.modal>

      <.confirm_dialog
        id="confirm-delete"
        show={@show_confirm}
        title={gettext("Excluir \"%{name}\"?", name: @file.nome)}
        message={gettext("Vai para a lixeira. Dá para restaurar em até 30 dias.")}
        on_confirm="confirm-delete"
        on_cancel={JS.push("close-confirm")}
      />

      <.modal id="confirm-zona" show={@show_zona} on_cancel={JS.push("close-zona")}>
        <h2 class="type-h3 mb-2">{zona_confirm_title(@file.zona, @file.nome)}</h2>
        <p class="type-body text-secondary mb-6">{zona_confirm_body(@file.zona)}</p>
        <div class="row gap-3">
          <.button variant="secondary" size="md" class="flex-1" phx-click="close-zona">
            {gettext("Cancelar")}
          </.button>
          <.button variant="primary" size="md" class="flex-1" phx-click="confirm-zona">
            {zona_confirm_primary(@file.zona)}
          </.button>
        </div>
      </.modal>
    </Layouts.app>
    """
  end
end
