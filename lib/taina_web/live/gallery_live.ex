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

  Zonas casa/praca (RFC_003): o filtro mora na URL (`?zona=casa` /
  `?zona=praca`; sem parametro a aba e Tudo, o conjunto legivel da
  comunidade), cada tile carrega o badge da zona, o modal de Detalhes diz
  quem ve, e o visualizador tem a alavanca "Publicar na praça" / "Tirar da
  praça" para quem é dono.
  """

  use TainaWeb, :live_view

  alias Taina.Jaci
  alias Taina.Ybira
  alias TainaWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Fotos"))
     |> assign(:zona, :tudo)
     |> assign(:grid_zona, nil)
     |> assign(:timeline_zona, nil)
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
     |> assign(:show_zona, false)
     |> stream(:photos, [])
     |> stream_configure(:timeline_groups, dom_id: &timeline_dom_id/1)
     |> stream(:timeline_groups, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    zona = parse_zona(params["zona"])

    case socket.assigns.live_action do
      :grid -> {:noreply, socket |> assign(:zona, zona) |> ensure_grid()}
      :timeline -> {:noreply, socket |> assign(:zona, zona) |> ensure_timeline()}
      :viewer -> {:noreply, open_viewer(socket, params["id"])}
    end
  end

  # A grade e a linha do tempo dividem a mesma tela: quando uma entra, a
  # outra sai do DOM (o `:if` desmonta o container do stream) e o LiveView
  # poda os itens pendentes, então a flag `*_stale` obriga o refetch na
  # volta. O visualizador é a exceção: os dois containers seguem montados
  # embaixo dele (`:if` inclui :viewer), então fechar e trocar de aba volta
  # sem refetch, com o scroll onde estava. Trocar a zona na URL é o outro
  # caminho de refetch: o fast path só vale com a MESMA zona carregada.
  defp ensure_grid(%{assigns: %{grid_stale: false, grid_zona: zona, zona: zona}} = socket) do
    socket
    |> assign(:current, nil)
    |> assign(:timeline_stale, true)
  end

  defp ensure_grid(socket) do
    socket = assign(socket, :timeline_stale, true)

    case Jaci.list_photos(socket.assigns.current_scope) do
      {:ok, %{items: photos, next_cursor: cursor}} ->
        zona_photos = for_zona(photos, socket.assigns.zona)

        socket
        |> assign(:loaded, true)
        |> assign(:current, nil)
        |> assign(:next_cursor, cursor)
        |> assign(:photo_ids, Enum.map(zona_photos, & &1.rkey))
        |> assign(:grid_error, false)
        |> assign(:grid_stale, false)
        |> assign(:grid_zona, socket.assigns.zona)
        |> stream(:photos, zona_photos, reset: true)

      {:error, _reason} ->
        socket
        |> assign(:loaded, true)
        |> assign(:grid_error, true)
        |> Phoenix.LiveView.put_flash(:error, gettext("Não foi possível carregar as fotos agora."))
    end
  end

  defp ensure_timeline(%{assigns: %{timeline_stale: false, timeline_zona: zona, zona: zona}} = socket) do
    socket
    |> assign(:current, nil)
    |> assign(:grid_stale, true)
  end

  defp ensure_timeline(socket) do
    socket = assign(socket, :grid_stale, true)

    case Jaci.timeline(socket.assigns.current_scope) do
      {:ok, %{groups: groups, next_cursor: cursor}} ->
        zona_groups = for_zona_groups(groups, socket.assigns.zona)

        socket
        |> assign(:current, nil)
        |> assign(:last_group, List.last(zona_groups))
        |> assign(:timeline_cursor, cursor)
        |> assign(:timeline_empty, zona_groups == [])
        |> assign(:photo_ids, timeline_photo_ids(zona_groups))
        |> assign(:timeline_error, false)
        |> assign(:timeline_stale, false)
        |> assign(:timeline_zona, socket.assigns.zona)
        |> stream(:timeline_groups, zona_groups, reset: true, dom_id: &timeline_dom_id/1)

      {:error, _reason} ->
        socket
        |> assign(:timeline_error, true)
        |> Phoenix.LiveView.put_flash(:error, gettext("Não foi possível carregar as fotos agora."))
    end
  end

  defp timeline_photo_ids(groups) do
    for group <- groups, photo <- group.photos, do: photo.rkey
  end

  defp open_viewer(socket, rkey) do
    case Ybira.get_file(socket.assigns.current_scope, rkey) do
      {:ok, file} ->
        socket
        |> assign(:current, file)
        |> assign_new_ids(rkey)

      # Casa de outra pessoa: a tela de preview é quem explica o "Pedir
      # acesso"; aqui só levamos a pessoa até lá.
      {:error, :forbidden} ->
        Phoenix.LiveView.push_navigate(socket, to: ~p"/arquivos/#{rkey}")

      {:error, :not_found} ->
        socket
        |> Phoenix.LiveView.put_flash(:error, gettext("Foto não encontrada."))
        |> Phoenix.LiveView.push_patch(to: ~p"/fotos")
    end
  end

  # Link direto para /fotos/:id (sem grade carregada): navega só esta foto.
  defp assign_new_ids(%{assigns: %{photo_ids: []}} = socket, rkey) do
    assign(socket, :photo_ids, [rkey])
  end

  defp assign_new_ids(socket, _rkey), do: socket

  @impl true
  def handle_event("load-more", _params, socket) do
    case {socket.assigns.live_action, socket.assigns.next_cursor, socket.assigns.timeline_cursor} do
      {:grid, cursor, _t} when is_binary(cursor) ->
        case Jaci.list_photos(socket.assigns.current_scope, after_cursor: cursor) do
          {:ok, %{items: photos, next_cursor: next_cursor}} ->
            zona_photos = for_zona(photos, socket.assigns.zona)

            {:noreply,
             socket
             |> assign(:next_cursor, next_cursor)
             |> assign(:photo_ids, socket.assigns.photo_ids ++ Enum.map(zona_photos, & &1.rkey))
             |> stream(:photos, zona_photos)}

          {:error, _reason} ->
            {:noreply, Phoenix.LiveView.put_flash(socket, :error, gettext("Não foi possível carregar mais fotos agora."))}
        end

      {:timeline, _g, cursor} when is_binary(cursor) ->
        case Jaci.timeline(socket.assigns.current_scope, after_cursor: cursor) do
          {:ok, %{groups: groups, next_cursor: next_cursor}} ->
            zona_groups = for_zona_groups(groups, socket.assigns.zona)
            {last_group, stream_page} = extend_timeline(socket.assigns.last_group, zona_groups)

            {:noreply,
             socket
             |> assign(:last_group, last_group)
             |> assign(:timeline_cursor, next_cursor)
             |> assign(:photo_ids, socket.assigns.photo_ids ++ timeline_photo_ids(zona_groups))
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
      {:noreply, Phoenix.LiveView.push_patch(socket, to: gallery_path(:grid, socket.assigns.zona))}
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

  # Publicar/tirar da praça no visualizador: a zona do arquivo é o
  # consentimento (RFC_003), então a alavanca mora aqui também, não só em
  # Arquivos. O contexto valida dono e zona; a tela espelha o que voltou.
  def handle_event("ask-zona", _params, socket) do
    {:noreply, assign(socket, :show_zona, true)}
  end

  def handle_event("close-zona", _params, socket) do
    {:noreply, assign(socket, :show_zona, false)}
  end

  def handle_event("confirm-zona", _params, %{assigns: %{current: current}} = socket) do
    scope = socket.assigns.current_scope

    result =
      case current.zona do
        :casa -> Ybira.publicar_file(scope, current.rkey)
        :praca -> Ybira.tirar_file_da_praca(scope, current.rkey)
      end

    case result do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:current, updated)
         |> assign(:show_zona, false)
         |> mark_zone_changed()
         |> Phoenix.LiveView.put_flash(:info, zona_flash_ok(current.zona))}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:show_zona, false)
         |> Phoenix.LiveView.put_flash(:error, zona_flash_error(current.zona))}
    end
  end

  def handle_event("confirm-zona", _params, socket) do
    {:noreply, assign(socket, :show_zona, false)}
  end

  def handle_event("confirm-delete", _params, %{assigns: %{current: %{rkey: rkey}}} = socket) do
    case Ybira.delete_file(socket.assigns.current_scope, rkey) do
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

  defp modal_open?(%{show_confirm: show_confirm, show_details: show_details, show_zona: show_zona}) do
    show_confirm or show_details or show_zona
  end

  # Publicar muda o badge nos tiles embaixo do visualizador: as duas visões
  # recarregam na volta. Os ids seguem em mãos, a navegação não pula.
  defp mark_zone_changed(socket) do
    socket
    |> assign(:grid_stale, true)
    |> assign(:timeline_stale, true)
  end

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
    current_id = socket.assigns.current && socket.assigns.current.rkey

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
  # Página vazia (o filtro casa/praca pode esvaziar uma página inteira)
  # devolve a âncora intacta: o dia pode continuar na próxima página.
  defp extend_timeline(last_group, []), do: {last_group, []}

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

  defp viewer_index(ids, %{rkey: id}), do: (Enum.find_index(ids, &(&1 == id)) || 0) + 1

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

  defp video?(%{mime: mime}), do: String.starts_with?(mime, "video/")

  # --- zonas casa/praca (RFC_003 D1/D2) ---

  # Zona na URL, como em Arquivos; a diferenca e o default: Fotos e a galeria
  # da comunidade (o conjunto legivel inteiro), entao sem parametro a aba e
  # Tudo. ?zona=casa e ?zona=praca estreitam a leitura; a abertura do upload
  # nunca "some", porque Tudo inclui a casa.
  defp parse_zona("praca"), do: :praca
  defp parse_zona("casa"), do: :casa
  defp parse_zona(_tudo_default), do: :tudo

  # Particao client-side, como em Arquivos: a leitura trouxe o conjunto
  # legivel, aqui so escolhemos o que a aba mostra.
  defp for_zona(photos, :tudo), do: photos
  defp for_zona(photos, zona), do: Enum.filter(photos, &(&1.zona == zona))

  # A linha do tempo chega agrupada por dia; o filtro pode esvaziar um dia
  # que so tinha foto da outra zona, e o dia vazio sai da lista.
  defp for_zona_groups(groups, :tudo), do: groups

  defp for_zona_groups(groups, zona) do
    for %{photos: photos} = group <- groups,
        zona_photos = Enum.filter(photos, &(&1.zona == zona)),
        zona_photos != [] do
      %{group | photos: zona_photos}
    end
  end

  defp gallery_path(:grid, :tudo), do: ~p"/fotos"
  defp gallery_path(:grid, :praca), do: ~p"/fotos?#{[zona: "praca"]}"
  defp gallery_path(:grid, :casa), do: ~p"/fotos?#{[zona: "casa"]}"

  defp gallery_path(:timeline, :tudo), do: ~p"/fotos/linha-do-tempo"
  defp gallery_path(:timeline, :praca), do: ~p"/fotos/linha-do-tempo?#{[zona: "praca"]}"
  defp gallery_path(:timeline, :casa), do: ~p"/fotos/linha-do-tempo?#{[zona: "casa"]}"

  defp view_action(:timeline), do: :timeline
  defp view_action(_grade_default), do: :grid

  # Badge do tile: as mesmas palavras das abas, sem metáfora nova.
  defp zona_short(:praca), do: gettext("Praça")
  defp zona_short(:casa), do: gettext("Casa")

  # A zona nomeada no Detalhes: a palavra da aba e a leitura de quem vê.
  defp zona_long(:praca), do: gettext("Na praça: todos os moradores veem.")
  defp zona_long(:casa), do: gettext("Na sua casa: só você, e quem você deixar.")

  # A acao oferecida e sempre a oposta da zona atual.
  defp zona_action_label(:casa), do: gettext("Publicar na praça")
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

  defp own?(scope, file), do: scope.ava.id == file.dono_id

  # Troca progressiva do visualizador: o `md` carrega primeiro e o JS troca
  # para o original depois. O original só entra no plano quando o tamanho
  # cabe no orçamento do Pi; arquivo gigante demais trava a caixa por causa
  # de um preview. O JS lê o `data-full` do `img`: sem atributo, sem troca.
  @full_swap_cap_bytes 20 * 1024 * 1024

  defp full_swap?(%{tamanho: bytes}), do: bytes <= @full_swap_cap_bytes

  # Tipo legível: "image/jpeg" vira "Imagem JPEG" (o kind do design system
  # traduzido, o subtipo em maiúsculas). "application/pdf" vira só "PDF",
  # sem repetir o subtipo quando ele já é o nome curto.
  defp human_type(%{mime: mime}) do
    kind = file_kind(mime)
    subtype = mime |> String.split("/") |> List.last() |> String.upcase()

    if kind == subtype, do: kind, else: "#{kind} #{subtype}"
  end

  # A data do visualizador vem do upload (o kernel nao carrega os metadados
  # de rendicao); a linha do tempo agrupa pela data efetiva, resolvida na
  # consulta do Jaci.
  defp photo_date(file) do
    file.inserted_at
    |> NaiveDateTime.to_date()
    |> Calendar.strftime("%d/%m/%Y")
  end

  # O estado vazio diz a verdade sobre a aba: em Tudo fala da comunidade; na
  # casa, das suas fotos; na praca, das publicadas.
  defp photo_empty_copy(:tudo),
    do: {gettext("Nenhuma foto ainda"), gettext("As imagens que a comunidade enviar aparecem aqui.")}

  defp photo_empty_copy(:casa),
    do:
      {gettext("Nenhuma foto sua ainda"),
       gettext("As fotos que você enviar ficam aqui, na sua casa. Publique na praça para todos verem.")}

  defp photo_empty_copy(:praca),
    do: {gettext("A praça está vazia"), gettext("As fotos publicadas para a comunidade aparecem aqui.")}

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

      <div class="row between wrap gap-3">
        <.segmented>
          <:option patch={gallery_path(:grid, @zona)} current={@live_action == :grid}>
            {gettext("Grade")}
          </:option>
          <:option patch={gallery_path(:timeline, @zona)} current={@live_action == :timeline}>
            {gettext("Linha do tempo")}
          </:option>
        </.segmented>

        <.segmented>
          <:option patch={gallery_path(view_action(@live_action), :tudo)} current={@zona == :tudo}>
            {gettext("Tudo")}
          </:option>
          <:option patch={gallery_path(view_action(@live_action), :praca)} current={@zona == :praca}>
            {gettext("Praça")}
          </:option>
          <:option patch={gallery_path(view_action(@live_action), :casa)} current={@zona == :casa}>
            {gettext("Casa")}
          </:option>
        </.segmented>
      </div>

      <div :if={@live_action in [:grid, :viewer]} class="mt-4">
        <div id="photo-grid" class="photo-grid" phx-update="stream">
          <.link
            :for={{dom_id, photo} <- @streams.photos}
            id={dom_id}
            patch={~p"/fotos/#{photo.rkey}"}
            class="photo-grid__item"
            aria-label={photo.nome}
          >
            <span class="photo-grid__tag">{zona_short(photo.zona)}</span>
            <div :if={video?(photo)} class="photo-grid__video">
              <.icon name="play" size={28} />
            </div>
            <img
              :if={!video?(photo)}
              src={~p"/files/#{photo.rkey}/thumbnail/sm"}
              alt={photo.nome}
              loading="lazy"
            />
          </.link>
        </div>

        <div :if={@next_cursor} id="grid-load-more" phx-viewport-bottom="load-more" class="center py-4">
          <p class="type-caption text-muted">{gettext("Carregando mais...")}</p>
        </div>

        <% {empty_title, empty_hint} = photo_empty_copy(@zona) %>

        <.empty_state
          :if={@loaded && @photo_ids == [] and not @grid_error}
          icon="image"
          title={empty_title}
          hint={empty_hint}
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
                patch={~p"/fotos/#{photo.rkey}"}
                class="photo-grid__item"
                aria-label={photo.nome}
              >
                <span class="photo-grid__tag">{zona_short(photo.zona)}</span>
                <div :if={video?(photo)} class="photo-grid__video">
                  <.icon name="play" size={28} />
                </div>
                <img
                  :if={!video?(photo)}
                  src={~p"/files/#{photo.rkey}/thumbnail/sm"}
                  alt={photo.nome}
                  loading="lazy"
                />
              </.link>
            </div>
          </section>
        </div>

        <div :if={@timeline_cursor} id="timeline-load-more" phx-viewport-bottom="load-more" class="center py-4">
          <p class="type-caption text-muted">{gettext("Carregando mais...")}</p>
        </div>

        <% {empty_title, empty_hint} = photo_empty_copy(@zona) %>

        <.empty_state
          :if={@live_action == :timeline and @timeline_empty and not @timeline_error}
          icon="image"
          title={empty_title}
          hint={empty_hint}
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
            data-copy={url(~p"/files/#{@current.rkey}")}
          />
        </header>

        <div class="viewer__stage">
          <video
            :if={video?(@current)}
            controls
            preload="metadata"
            playsinline
            src={~p"/files/#{@current.rkey}"}
          ></video>
          <img
            :if={!video?(@current)}
            id="viewer-full-swap"
            phx-hook="FullSwap"
            src={~p"/files/#{@current.rkey}/thumbnail/md"}
            data-full={full_swap?(@current) && url(~p"/files/#{@current.rkey}")}
            alt={@current.nome}
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
            :for={{id, position} <- rail_window(@photo_ids, @current.rkey)}
            id={"rail-#{id}"}
            patch={~p"/fotos/#{id}"}
            class="viewer__rail-item"
            aria-current={id == @current.rkey}
            aria-label={gettext("Foto %{index} de %{total}", index: position, total: length(@photo_ids))}
          >
            <span class="viewer__rail-thumb" style={"background-image: url('#{~p"/files/#{id}/thumbnail/sm"}')"}></span>
          </.link>
        </nav>

        <p class="viewer__caption">{@current.nome}</p>

        <div class="viewer__actions">
          <button
            type="button"
            class="viewer__action"
            id="viewer-share"
            phx-hook="Share"
            data-url={url(~p"/files/#{@current.rkey}")}
            data-title={@current.nome}
          >
            <.icon name="share" size={20} />
            <span>{gettext("Compartilhar")}</span>
          </button>
          <a href={~p"/files/#{@current.rkey}"} download class="viewer__action">
            <.icon name="download" size={20} />
            <span>{gettext("Baixar")}</span>
          </a>
          <button
            :if={own?(@current_scope, @current)}
            type="button"
            class="viewer__action"
            phx-click="ask-zona"
          >
            <.icon name="eye" size={20} />
            <span>{zona_action_label(@current.zona)}</span>
          </button>
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
        title={gettext("Excluir \"%{name}\"?", name: @current.nome)}
        message={gettext("Vai para a lixeira. Dá para restaurar em até 30 dias.")}
        on_confirm="confirm-delete"
        on_cancel={JS.push("close-confirm")}
      />

      <.modal :if={@current} id="photo-details" show={@show_details} on_cancel={JS.push("toggle-details")}>
        <h2 class="type-h3 mb-4">{gettext("Detalhes")}</h2>
        <div class="col gap-3">
          <div>
            <p class="type-caption text-faint">{gettext("Quem vê")}</p>
            <p class="type-body">{zona_long(@current.zona)}</p>
          </div>
          <div>
            <p class="type-caption text-faint">{gettext("Nome original")}</p>
            <p class="type-body">{@current.nome}</p>
          </div>
          <% file_url = url(~p"/files/#{@current.rkey}") %>
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
            <p class="type-body">{format_bytes(@current.tamanho)}</p>
          </div>
          <div>
            <p class="type-caption text-faint">{gettext("Assinatura do arquivo")}</p>
            <p class="type-mono-sm truncate">{@current.hash}</p>
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

      <.modal id="confirm-zona" show={@show_zona} on_cancel={JS.push("close-zona")}>
        <div :if={@current}>
          <h2 class="type-h3 mb-2">{zona_confirm_title(@current.zona, @current.nome)}</h2>
          <p class="type-body text-secondary mb-6">{zona_confirm_body(@current.zona)}</p>
          <div class="row gap-3">
            <.button variant="secondary" size="md" class="flex-1" phx-click="close-zona">
              {gettext("Cancelar")}
            </.button>
            <.button variant="primary" size="md" class="flex-1" phx-click="confirm-zona">
              {zona_confirm_primary(@current.zona)}
            </.button>
          </div>
        </div>
      </.modal>
    </Layouts.app>
    """
  end
end
