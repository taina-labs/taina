defmodule TainaWeb.GalleryLive do
  @moduledoc """
  Jaci-lite (telas "Jaci - Grade", "Jaci - Linha do tempo" e "Jaci -
  Visualizador"): grade 2/6/8/10 colunas (mobile/tablet/desktop/largo) com
  scroll infinito (`phx-viewport-bottom` + cursor keyset do Jaci), linha do
  tempo agrupada por dia e visualizador fullscreen com navegação por
  teclado/swipe (hook `ViewerNav`); no desktop (1024+) o visualizador ganha
  uma barra de fotos vizinhas no lugar de só setas, e a foto troca do
  thumbnail `md` para o original em segundo plano (hook `FullSwap`).

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
     |> assign(:timeline_cursor, nil)
     |> assign(:current, nil)
     |> assign(:loaded, false)
     |> assign(:grid_stale, true)
     |> assign(:timeline_stale, true)
     |> assign(:grid_error, false)
     |> assign(:timeline_error, false)
     |> assign(:timeline_empty, true)
     |> assign(:last_group, nil)
     |> assign(:show_confirm, false)
     |> assign(:show_details, false)
     |> stream(:photos, [])
     |> stream_configure(:timeline_groups, dom_id: &timeline_dom_id/1)
     |> stream(:timeline_groups, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case socket.assigns.live_action do
      :grid -> {:noreply, ensure_grid(socket)}
      :timeline -> {:noreply, ensure_timeline(socket)}
      :viewer -> {:noreply, open_viewer(socket, params["id"])}
    end
  end

  # A grade e a linha do tempo dividem a mesma tela: quando uma entra, a
  # outra sai do DOM (o `:if` desmonta o container do stream) e o LiveView
  # poda os itens pendentes, então a flag `*_stale` obriga o refetch na
  # volta. O visualizador é a exceção: os dois containers seguem montados
  # embaixo dele (`:if` inclui :viewer), então fechar e trocar de aba volta
  # sem refetch, com o scroll onde estava.
  defp ensure_grid(%{assigns: %{grid_stale: false}} = socket) do
    socket
    |> assign(:current, nil)
    |> assign(:timeline_stale, true)
  end

  defp ensure_grid(socket) do
    socket = assign(socket, :timeline_stale, true)

    case Jaci.list_photos(socket.assigns.current_scope) do
      {:ok, %{items: photos, next_cursor: cursor}} ->
        socket
        |> assign(:loaded, true)
        |> assign(:current, nil)
        |> assign(:next_cursor, cursor)
        |> assign(:photo_ids, Enum.map(photos, & &1.public_id))
        |> assign(:grid_error, false)
        |> assign(:grid_stale, false)
        |> stream(:photos, photos, reset: true)

      {:error, _reason} ->
        socket
        |> assign(:loaded, true)
        |> assign(:grid_error, true)
        |> Phoenix.LiveView.put_flash(:error, gettext("Não foi possível carregar as fotos agora."))
    end
  end

  defp ensure_timeline(%{assigns: %{timeline_stale: false}} = socket) do
    socket
    |> assign(:current, nil)
    |> assign(:grid_stale, true)
  end

  defp ensure_timeline(socket) do
    socket = assign(socket, :grid_stale, true)

    case Jaci.timeline(socket.assigns.current_scope) do
      {:ok, %{groups: groups, next_cursor: cursor}} ->
        socket
        |> assign(:current, nil)
        |> assign(:last_group, List.last(groups))
        |> assign(:timeline_cursor, cursor)
        |> assign(:timeline_empty, groups == [])
        |> assign(:photo_ids, timeline_photo_ids(groups))
        |> assign(:timeline_error, false)
        |> assign(:timeline_stale, false)
        |> stream(:timeline_groups, groups, reset: true, dom_id: &timeline_dom_id/1)

      {:error, _reason} ->
        socket
        |> assign(:timeline_error, true)
        |> Phoenix.LiveView.put_flash(:error, gettext("Não foi possível carregar as fotos agora."))
    end
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

      # Casa de outra pessoa: a tela de preview é quem explica o "Pedir
      # acesso"; aqui só levamos a pessoa até lá.
      {:error, :forbidden} ->
        Phoenix.LiveView.push_navigate(socket, to: ~p"/arquivos/#{public_id}")

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
        case Jaci.list_photos(socket.assigns.current_scope, after_cursor: cursor) do
          {:ok, %{items: photos, next_cursor: next_cursor}} ->
            {:noreply,
             socket
             |> assign(:next_cursor, next_cursor)
             |> assign(:photo_ids, socket.assigns.photo_ids ++ Enum.map(photos, & &1.public_id))
             |> stream(:photos, photos)}

          {:error, _reason} ->
            {:noreply, Phoenix.LiveView.put_flash(socket, :error, gettext("Não foi possível carregar mais fotos agora."))}
        end

      {:timeline, _g, cursor} when is_binary(cursor) ->
        case Jaci.timeline(socket.assigns.current_scope, after_cursor: cursor) do
          {:ok, %{groups: groups, next_cursor: next_cursor}} ->
            {last_group, stream_page} = extend_timeline(socket.assigns.last_group, groups)

            {:noreply,
             socket
             |> assign(:last_group, last_group)
             |> assign(:timeline_cursor, next_cursor)
             |> assign(:photo_ids, socket.assigns.photo_ids ++ timeline_photo_ids(groups))
             |> stream(:timeline_groups, stream_page, dom_id: &timeline_dom_id/1)}

          {:error, _reason} ->
            {:noreply, Phoenix.LiveView.put_flash(socket, :error, gettext("Não foi possível carregar mais fotos agora."))}
        end

      _other ->
        {:noreply, socket}
    end
  end

  # Setas e Escape do visualizador: enquanto um modal está por cima (confirmar
  # exclusão, detalhes), a navegação espera. Um Escape não pode fechar o modal
  # e sair do visualizador junto.
  def handle_event("prev", _params, socket), do: {:noreply, guarded_step(socket, -1)}
  def handle_event("next", _params, socket), do: {:noreply, guarded_step(socket, +1)}

  def handle_event("close", _params, socket) do
    if modal_open?(socket.assigns) do
      {:noreply, socket}
    else
      {:noreply, Phoenix.LiveView.push_patch(socket, to: ~p"/fotos")}
    end
  end

  def handle_event("copied", _params, socket) do
    {:noreply, Phoenix.LiveView.put_flash(socket, :info, gettext("Link copiado!"))}
  end

  # A guarda de clipboard fica no hook (JS); quando ele não consegue copiar
  # (origem insegura, sem permissão), a saída é o Detalhes: o link aparece
  # lá em texto, pronto para copiar à mão.
  def handle_event("copy-failed", _params, socket) do
    {:noreply,
     Phoenix.LiveView.put_flash(
       socket,
       :error,
       gettext("Não deu para copiar agora. Toque em \"Detalhes\", toque no link e copie.")
     )}
  end

  def handle_event("retry", _params, socket) do
    case socket.assigns.live_action do
      :grid -> {:noreply, ensure_grid(socket)}
      :timeline -> {:noreply, ensure_timeline(socket)}
      _other -> {:noreply, socket}
    end
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

  defp guarded_step(socket, delta) do
    if modal_open?(socket.assigns), do: socket, else: step(socket, delta)
  end

  defp modal_open?(%{show_confirm: show_confirm, show_details: show_details}), do: show_confirm or show_details

  defp reset_gallery(socket) do
    socket
    |> assign(:loaded, false)
    |> assign(:grid_stale, true)
    |> assign(:timeline_stale, true)
    |> assign(:photo_ids, [])
    |> assign(:last_group, nil)
    |> assign(:timeline_empty, true)
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
  # mesma data (ver `Taina.Jaci.Timeline.group_by_date/1`). Devolve o último
  # grupo do acumulado (tudo o que a fusão precisa guardar fora do stream) e
  # a página pronta para o stream: quando o dia se repete, o grupo fundido
  # entra com o mesmo id e atualiza o item no lugar, sem repetir o dia.
  defp extend_timeline(nil, new_groups), do: {List.last(new_groups), new_groups}

  defp extend_timeline(%{date: date} = last_group, [%{date: date} = first | rest]) do
    merged = %{first | photos: last_group.photos ++ first.photos}
    {List.last([merged | rest]), [merged | rest]}
  end

  defp extend_timeline(_last_group, new_groups), do: {List.last(new_groups), new_groups}

  # Um id por dia: o stream atualiza o grupo fundido no lugar em vez de
  # empilhar uma seção nova com o mesmo dia.
  defp timeline_dom_id(group), do: "timeline-group-#{group.date}"

  defp group_title(date) do
    case Date.diff(Date.utc_today(), date) do
      0 -> gettext("Hoje")
      1 -> gettext("Ontem")
      _days -> Calendar.strftime(date, "%d/%m/%Y")
    end
  end

  defp viewer_index(ids, %{public_id: id}), do: (Enum.find_index(ids, &(&1 == id)) || 0) + 1

  # Janela de fotos vizinhas para a barra do visualizador (desktop): um trecho
  # curto em volta da atual, não a lista inteira. `{id, posição}` para o rótulo
  # acessível de cada miniatura.
  @rail_window 10

  defp rail_window(ids, current_id) do
    case Enum.find_index(ids, &(&1 == current_id)) do
      nil ->
        []

      index ->
        first = max(index - @rail_window, 0)
        last = min(index + @rail_window, length(ids) - 1)

        for i <- first..last, do: {Enum.at(ids, i), i + 1}
    end
  end

  defp video?(%{mime_type: mime}), do: String.starts_with?(mime, "video/")

  # Troca progressiva do visualizador: o `md` carrega primeiro e o JS troca
  # para o original depois. O original só entra no plano quando o tamanho
  # cabe no orçamento do Pi; arquivo gigante demais trava a caixa por causa
  # de um preview. O JS lê o `data-full` do `img`: sem atributo, sem troca.
  @full_swap_cap_bytes 20 * 1024 * 1024

  defp full_swap?(%{file_size_bytes: bytes}), do: bytes <= @full_swap_cap_bytes

  # Tipo legível: "image/jpeg" vira "Imagem JPEG" (o kind do design system
  # traduzido, o subtipo em maiúsculas). "application/pdf" vira só "PDF",
  # sem repetir o subtipo quando ele já é o nome curto.
  defp human_type(%{mime_type: mime_type}) do
    kind = file_kind(mime_type)
    subtype = mime_type |> String.split("/") |> List.last() |> String.upcase()

    if kind == subtype, do: kind, else: "#{kind} #{subtype}"
  end

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
          <p class="type-caption text-muted">{gettext("Carregando mais...")}</p>
        </div>

        <.empty_state
          :if={@loaded && @photo_ids == [] and not @grid_error}
          icon="image"
          title={gettext("Nenhuma foto ainda")}
          hint={gettext("As imagens que a comunidade enviar aparecem aqui.")}
        >
          <.button variant="primary" size="md" navigate={~p"/arquivos/enviar"}>
            {gettext("Enviar fotos")}
          </.button>
        </.empty_state>

        <.empty_state
          :if={@grid_error}
          icon="alert"
          title={gettext("Não foi possível carregar")}
          hint={gettext("As fotos não responderam agora.")}
        >
          <.button variant="secondary" phx-click="retry">{gettext("Tentar de novo")}</.button>
        </.empty_state>
      </div>

      <div :if={@live_action in [:timeline, :viewer]} class="mt-4 col gap-5">
        <div id="timeline-groups" phx-update="stream" class="col gap-5">
          <section :for={{dom_id, group} <- @streams.timeline_groups} id={dom_id}>
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
        </div>

        <div :if={@timeline_cursor} id="timeline-load-more" phx-viewport-bottom="load-more" class="center py-4">
          <p class="type-caption text-muted">{gettext("Carregando mais...")}</p>
        </div>

        <.empty_state
          :if={@live_action == :timeline and @timeline_empty and not @timeline_error}
          icon="image"
          title={gettext("Nenhuma foto ainda")}
          hint={gettext("As imagens que a comunidade enviar aparecem aqui.")}
        >
          <.button variant="primary" size="md" navigate={~p"/arquivos/enviar"}>
            {gettext("Enviar fotos")}
          </.button>
        </.empty_state>

        <.empty_state
          :if={@live_action == :timeline and @timeline_error}
          icon="alert"
          title={gettext("Não foi possível carregar")}
          hint={gettext("As fotos não responderam agora.")}
        >
          <.button variant="secondary" phx-click="retry">{gettext("Tentar de novo")}</.button>
        </.empty_state>
      </div>

      <div
        :if={@current}
        id="viewer"
        class="viewer"
        role="dialog"
        aria-modal="true"
        aria-label={gettext("Visualizador de fotos")}
        phx-hook="ViewerNav"
      >
        <header class="row between p-4">
          <.icon_button name="close" label={gettext("Fechar")} id="viewer-close" phx-click="close" />
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
          <video
            :if={video?(@current)}
            controls
            preload="metadata"
            playsinline
            src={~p"/files/#{@current.public_id}"}
          ></video>
          <img
            :if={!video?(@current)}
            id="viewer-full-swap"
            phx-hook="FullSwap"
            src={~p"/files/#{@current.public_id}/thumbnail/md"}
            data-full={full_swap?(@current) && url(~p"/files/#{@current.public_id}")}
            alt={@current.original_filename}
          />
          <button
            :if={length(@photo_ids) > 1}
            type="button"
            class="viewer__nav viewer__nav--prev icon-btn"
            phx-click="prev"
            aria-label={gettext("Foto anterior")}
          >
            <.icon name="chevron-left" size={28} />
          </button>
          <button
            :if={length(@photo_ids) > 1}
            type="button"
            class="viewer__nav viewer__nav--next icon-btn"
            phx-click="next"
            aria-label={gettext("Próxima foto")}
          >
            <.icon name="chevron-right" size={28} />
          </button>
        </div>

        <nav :if={length(@photo_ids) > 1} class="viewer__rail" aria-label={gettext("Fotos vizinhas")}>
          <.link
            :for={{id, position} <- rail_window(@photo_ids, @current.public_id)}
            id={"rail-#{id}"}
            patch={~p"/fotos/#{id}"}
            class="viewer__rail-item"
            aria-current={id == @current.public_id}
            aria-label={gettext("Foto %{index} de %{total}", index: position, total: length(@photo_ids))}
          >
            <span class="viewer__rail-thumb" style={"background-image: url('#{~p"/files/#{id}/thumbnail/sm"}')"}></span>
          </.link>
        </nav>

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
          <% file_url = url(~p"/files/#{@current.public_id}") %>
          <div>
            <p class="type-caption text-faint">{gettext("Link")}</p>
            <p class="viewer__link type-mono-sm">{file_url}</p>
          </div>
          <div>
            <p class="type-caption text-faint">{gettext("Tipo")}</p>
            <p class="type-mono-sm">{human_type(@current)}</p>
          </div>
          <div>
            <p class="type-caption text-faint">{gettext("Tamanho")}</p>
            <p class="type-body">{format_bytes(@current.file_size_bytes)}</p>
          </div>
          <div>
            <p class="type-caption text-faint">{gettext("Assinatura do arquivo")}</p>
            <p class="type-mono-sm truncate">{@current.file_hash}</p>
            <p class="type-caption text-faint">{gettext("É como o Tainá confere que o arquivo está intacto.")}</p>
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
