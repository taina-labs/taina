defmodule TainaWeb.GalleryLive do
  @moduledoc """
  Jaci-lite (telas "Jaci - Grade", "Jaci - Linha do tempo" e "Jaci -
  Visualizador"): grade 3/6 colunas com scroll infinito (`phx-viewport-bottom`
  + cursor keyset do Jaci), linha do tempo agrupada por dia e visualizador
  fullscreen com navegação por teclado/swipe (hook `ViewerNav`).

  Thumbnails: `/files/:id/thumbnail/sm` (grade) e `md` (visualizador), o
  worker `Rendition` gera depois do upload; enquanto não há thumbnail, o
  controller responde 404 e o quadradinho fica com o fundo de superfície.
  """

  use TainaWeb, :live_view

  alias Taina.Jaci
  alias Taina.Jaci.Timeline
  alias Taina.Ybira
  alias TainaWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Fotos"))
     |> assign(:photo_ids, [])
     |> assign(:next_cursor, nil)
     |> assign(:groups, [])
     |> assign(:timeline_cursor, nil)
     |> assign(:current, nil)
     |> assign(:loaded, false)
     |> assign(:show_confirm, false)
     |> assign(:show_details, false)
     |> stream(:photos, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case socket.assigns.live_action do
      :grid -> {:noreply, ensure_grid(socket)}
      :timeline -> {:noreply, ensure_timeline(socket)}
      :viewer -> {:noreply, open_viewer(socket, params["id"])}
    end
  end

  # Sempre recarrega ao entrar na grade: o container do stream (`phx-update`)
  # é desmontado ao trocar de visão/visualizador, então um stream "lembrado"
  # voltaria vazio. Recarregar do zero garante render e reseta o scroll.
  defp ensure_grid(socket) do
    {:ok, %{items: photos, next_cursor: cursor}} = Jaci.list_photos(socket.assigns.current_scope)

    socket
    |> assign(:loaded, true)
    |> assign(:current, nil)
    |> assign(:next_cursor, cursor)
    |> assign(:photo_ids, Enum.map(photos, & &1.public_id))
    |> stream(:photos, photos, reset: true)
  end

  defp ensure_timeline(socket) do
    {:ok, %{groups: groups, next_cursor: cursor}} = Jaci.timeline(socket.assigns.current_scope)

    socket
    |> assign(:current, nil)
    |> assign(:groups, groups)
    |> assign(:timeline_cursor, cursor)
    |> assign(:photo_ids, timeline_photo_ids(groups))
  end

  defp timeline_photo_ids(groups) do
    for group <- groups, photo <- group.photos, do: photo.public_id
  end

  defp open_viewer(socket, public_id) do
    case Ybira.get_file(socket.assigns.current_scope, public_id) do
      {:ok, file} ->
        socket
        |> assign(:current, file)
        |> assign_new_ids(public_id)

      {:error, :not_found} ->
        socket
        |> Phoenix.LiveView.put_flash(:error, gettext("Foto não encontrada."))
        |> Phoenix.LiveView.push_patch(to: ~p"/fotos")
    end
  end

  # Link direto para /fotos/:id (sem grade carregada): navega só esta foto.
  defp assign_new_ids(%{assigns: %{photo_ids: []}} = socket, public_id) do
    assign(socket, :photo_ids, [public_id])
  end

  defp assign_new_ids(socket, _public_id), do: socket

  @impl true
  def handle_event("load-more", _params, socket) do
    case {socket.assigns.live_action, socket.assigns.next_cursor, socket.assigns.timeline_cursor} do
      {:grid, cursor, _t} when is_binary(cursor) ->
        {:ok, %{items: photos, next_cursor: next_cursor}} =
          Jaci.list_photos(socket.assigns.current_scope, after_cursor: cursor)

        {:noreply,
         socket
         |> assign(:next_cursor, next_cursor)
         |> assign(:photo_ids, socket.assigns.photo_ids ++ Enum.map(photos, & &1.public_id))
         |> stream(:photos, photos)}

      {:timeline, _g, cursor} when is_binary(cursor) ->
        {:ok, %{groups: groups, next_cursor: next_cursor}} =
          Jaci.timeline(socket.assigns.current_scope, after_cursor: cursor)

        {:noreply,
         socket
         |> assign(:timeline_cursor, next_cursor)
         |> assign(:photo_ids, socket.assigns.photo_ids ++ timeline_photo_ids(groups))
         |> assign(:groups, merge_groups(socket.assigns.groups, groups))}

      _other ->
        {:noreply, socket}
    end
  end

  def handle_event("prev", _params, socket), do: {:noreply, step(socket, -1)}
  def handle_event("next", _params, socket), do: {:noreply, step(socket, +1)}

  def handle_event("close", _params, socket) do
    {:noreply, Phoenix.LiveView.push_patch(socket, to: ~p"/fotos")}
  end

  def handle_event("copied", _params, socket) do
    {:noreply, Phoenix.LiveView.put_flash(socket, :info, gettext("Link copiado!"))}
  end

  def handle_event("ask-delete", _params, socket) do
    {:noreply, assign(socket, :show_confirm, true)}
  end

  def handle_event("close-confirm", _params, socket) do
    {:noreply, assign(socket, :show_confirm, false)}
  end

  def handle_event("toggle-details", _params, socket) do
    {:noreply, assign(socket, :show_details, !socket.assigns.show_details)}
  end

  def handle_event("confirm-delete", _params, %{assigns: %{current: %{public_id: public_id}}} = socket) do
    case Ybira.delete_file(socket.assigns.current_scope, public_id) do
      {:ok, _file} ->
        {:noreply,
         socket
         |> assign(:show_confirm, false)
         |> Phoenix.LiveView.put_flash(:info, gettext("Foto movida para a lixeira."))
         |> reset_gallery()
         |> Phoenix.LiveView.push_patch(to: ~p"/fotos")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:show_confirm, false)
         |> Phoenix.LiveView.put_flash(:error, gettext("Não foi possível excluir a foto."))}
    end
  end

  def handle_event("confirm-delete", _params, socket) do
    {:noreply, assign(socket, :show_confirm, false)}
  end

  defp reset_gallery(socket) do
    socket
    |> assign(:loaded, false)
    |> assign(:groups, [])
    |> assign(:photo_ids, [])
  end

  defp step(socket, delta) do
    ids = socket.assigns.photo_ids
    current_id = socket.assigns.current && socket.assigns.current.public_id

    with index when is_integer(index) <- current_id && Enum.find_index(ids, &(&1 == current_id)),
         next_index = index + delta,
         true <- next_index >= 0 and next_index < length(ids) do
      Phoenix.LiveView.push_patch(socket, to: ~p"/fotos/#{Enum.at(ids, next_index)}")
    else
      _out_of_range -> socket
    end
  end

  # Paginação pode partir um dia entre páginas; funde grupos adjacentes de
  # mesma data (ver `Taina.Jaci.Timeline.group_by_date/1`).
  defp merge_groups(groups, []), do: groups
  defp merge_groups([], new_groups), do: new_groups

  defp merge_groups(groups, [first | rest] = new_groups) do
    {head, [last]} = Enum.split(groups, -1)

    if last.date == first.date do
      head ++ [%{last | photos: last.photos ++ first.photos} | rest]
    else
      groups ++ new_groups
    end
  end

  defp group_title(date) do
    case Date.diff(Date.utc_today(), date) do
      0 -> gettext("Hoje")
      1 -> gettext("Ontem")
      _days -> Calendar.strftime(date, "%d/%m/%Y")
    end
  end

  defp viewer_index(ids, %{public_id: id}), do: (Enum.find_index(ids, &(&1 == id)) || 0) + 1

  defp video?(%{mime_type: mime}), do: String.starts_with?(mime, "video/")

  defp photo_date(file) do
    file
    |> Timeline.effective_datetime()
    |> NaiveDateTime.to_date()
    |> Calendar.strftime("%d/%m/%Y")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active_tab={:photos}
      storage_stats={assigns[:storage_stats]}
      account_alert={assigns[:account_alert] || false}
    >
      <h1 class="type-h1 mb-4">{gettext("Fotos")}</h1>

      <.segmented>
        <:option patch={~p"/fotos"} current={@live_action == :grid}>{gettext("Grade")}</:option>
        <:option patch={~p"/fotos/linha-do-tempo"} current={@live_action == :timeline}>
          {gettext("Linha do tempo")}
        </:option>
      </.segmented>

      <div :if={@live_action in [:grid, :viewer]} class="mt-4">
        <div id="photo-grid" class="photo-grid" phx-update="stream">
          <.link
            :for={{dom_id, photo} <- @streams.photos}
            id={dom_id}
            patch={~p"/fotos/#{photo.public_id}"}
            class="photo-grid__item"
            aria-label={photo.original_filename}
          >
            <div :if={video?(photo)} class="photo-grid__video">
              <.icon name="play" size={28} />
            </div>
            <img
              :if={!video?(photo)}
              src={~p"/files/#{photo.public_id}/thumbnail/sm"}
              alt={photo.original_filename}
              loading="lazy"
            />
          </.link>
        </div>

        <div :if={@next_cursor} id="grid-load-more" phx-viewport-bottom="load-more" class="center py-4">
          <p class="type-caption text-faint">{gettext("Carregando mais...")}</p>
        </div>

        <.empty_state
          :if={@loaded && @photo_ids == []}
          icon="image"
          title={gettext("Nenhuma foto ainda")}
          hint={gettext("As imagens que a comunidade enviar aparecem aqui.")}
        >
          <.button variant="primary" size="md" navigate={~p"/arquivos/enviar"}>
            {gettext("Enviar fotos")}
          </.button>
        </.empty_state>
      </div>

      <div :if={@live_action == :timeline} class="mt-4 col gap-5">
        <section :for={group <- @groups}>
          <h2 class="type-h3 mb-2">
            {group_title(group.date)}, {ngettext("%{count} foto", "%{count} fotos", length(group.photos))}
          </h2>
          <div class="photo-grid">
            <.link
              :for={photo <- group.photos}
              patch={~p"/fotos/#{photo.public_id}"}
              class="photo-grid__item"
              aria-label={photo.original_filename}
            >
              <div :if={video?(photo)} class="photo-grid__video">
                <.icon name="play" size={28} />
              </div>
              <img
                :if={!video?(photo)}
                src={~p"/files/#{photo.public_id}/thumbnail/sm"}
                alt={photo.original_filename}
                loading="lazy"
              />
            </.link>
          </div>
        </section>

        <div :if={@timeline_cursor} id="timeline-load-more" phx-viewport-bottom="load-more" class="center py-4">
          <p class="type-caption text-faint">{gettext("Carregando mais...")}</p>
        </div>

        <.empty_state
          :if={@groups == []}
          icon="image"
          title={gettext("Nenhuma foto ainda")}
          hint={gettext("As imagens que a comunidade enviar aparecem aqui.")}
        />
      </div>

      <div :if={@current} id="viewer" class="viewer" phx-hook="ViewerNav">
        <header class="row between p-4">
          <.icon_button name="close" label={gettext("Fechar")} phx-click="close" />
          <div class="text-center">
            <p class="type-label">{photo_date(@current)}</p>
            <p class="type-caption text-faint">
              {gettext("%{index} de %{total}", index: viewer_index(@photo_ids, @current), total: length(@photo_ids))}
            </p>
          </div>
          <.icon_button
            name="link"
            label={gettext("Copiar link")}
            id="viewer-copy-link"
            phx-hook="Clipboard"
            data-copy={url(~p"/files/#{@current.public_id}")}
          />
        </header>

        <div class="viewer__stage">
          <video :if={video?(@current)} controls src={~p"/files/#{@current.public_id}"}></video>
          <img
            :if={!video?(@current)}
            src={~p"/files/#{@current.public_id}/thumbnail/md"}
            alt={@current.original_filename}
          />
          <button
            type="button"
            class="viewer__nav viewer__nav--prev icon-btn"
            phx-click="prev"
            aria-label={gettext("Foto anterior")}
          >
            <.icon name="chevron-left" size={28} />
          </button>
          <button
            type="button"
            class="viewer__nav viewer__nav--next icon-btn"
            phx-click="next"
            aria-label={gettext("Próxima foto")}
          >
            <.icon name="chevron-right" size={28} />
          </button>
        </div>

        <p class="viewer__caption">{@current.original_filename}</p>

        <div class="viewer__actions">
          <button
            type="button"
            class="viewer__action"
            id="viewer-share"
            phx-hook="Share"
            data-url={url(~p"/files/#{@current.public_id}")}
            data-title={@current.original_filename}
          >
            <.icon name="share" size={20} />
            <span>{gettext("Compartilhar")}</span>
          </button>
          <a href={~p"/files/#{@current.public_id}"} download class="viewer__action">
            <.icon name="download" size={20} />
            <span>{gettext("Baixar")}</span>
          </a>
          <button type="button" class="viewer__action" phx-click="toggle-details">
            <.icon name="shield" size={20} />
            <span>{gettext("Detalhes")}</span>
          </button>
          <button type="button" class="viewer__action viewer__action--danger" phx-click="ask-delete">
            <.icon name="trash" size={20} />
            <span>{gettext("Excluir")}</span>
          </button>
        </div>
      </div>

      <.confirm_dialog
        :if={@current}
        id="confirm-delete-photo"
        show={@show_confirm}
        title={gettext("Excluir \"%{name}\"?", name: @current.original_filename)}
        message={gettext("Vai para a lixeira. Dá para restaurar em até 30 dias.")}
        on_confirm="confirm-delete"
        on_cancel={JS.push("close-confirm")}
      />

      <.modal :if={@current} id="photo-details" show={@show_details} on_cancel={JS.push("toggle-details")}>
        <h2 class="type-h3 mb-4">{gettext("Detalhes")}</h2>
        <div class="col gap-3">
          <div>
            <p class="type-caption text-faint">{gettext("Nome original")}</p>
            <p class="type-body">{@current.original_filename}</p>
          </div>
          <div>
            <p class="type-caption text-faint">{gettext("Tipo")}</p>
            <p class="type-mono-sm">{@current.mime_type}</p>
          </div>
          <div>
            <p class="type-caption text-faint">{gettext("Tamanho")}</p>
            <p class="type-body">{format_bytes(@current.file_size_bytes)}</p>
          </div>
          <div>
            <p class="type-caption text-faint">{gettext("SHA-256")}</p>
            <p class="type-mono-sm truncate">{@current.file_hash}</p>
          </div>
          <div>
            <p class="type-caption text-faint">{gettext("Enviado em")}</p>
            <p class="type-body">{Calendar.strftime(@current.inserted_at, "%d/%m/%Y %H:%M")}</p>
          </div>
        </div>
        <.button variant="secondary" class="w-full mt-6" phx-click="toggle-details">
          {gettext("Fechar")}
        </.button>
      </.modal>
    </Layouts.app>
    """
  end
end
