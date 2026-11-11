defmodule TainaWeb.GalleryLive do
  @moduledoc """
  Galeria (docs/web-revamp-spec.md 6.3; boards "Servico / Jaci" do Penpot:
  Grade padrão cc1037dc-e8ab-80cc-8008-d5e30853df7a, Grade vazio
  cc1037dc-e8ab-80cc-8008-d5e30c38d7b4, Grade carregando
  cc1037dc-e8ab-80cc-8008-d5e30ea0ed1f, Linha padrão
  cc1037dc-e8ab-80cc-8008-d5e3116dc761, Visualizador padrão
  cc1037dc-e8ab-80cc-8008-d5e315453160 e Visualizador erro
  cc1037dc-e8ab-80cc-8008-d5e315f7b931).

  As abas Grade e Linha do tempo são ROTAS (`/galeria` e
  `/galeria/linha-do-tempo`): a barra de abas vem da casca `service` (fixa no
  pé do celular, fileira sob o cabeçalho no desktop) e não há segmented. A
  zona casa/praca (RFC_003) segue viva na URL (`?zona=casa` / `?zona=praca`;
  sem parâmetro, o conjunto legível da comunidade), mas os boards não desenham
  filtro de zona em tela nenhuma: quem chega por link antigo continua lendo o
  conjunto certo, sem controle a mais na cara.

  A grade rola em página infinita (`phx-viewport-bottom` + cursor keyset do
  Jaci) com esqueleto `photo_grid` no lugar de spinner, e a linha do tempo
  agrupa por dia com o dia escrito ("4 de outubro", board). O FAB "Enviar"
  leva a `/documentos/enviar`: toda foto nasce na casa; no desktop o mesmo
  "Enviar" mora no cabeçalho (a troca é do CSS, os dois ficam no DOM).

  O visualizador é fullscreen (casco `viewer`) com navegação por teclado e
  swipe (hook `ViewerNav`) e troca do thumbnail `md` para o original em
  segundo plano (hook `FullSwap`). Quando a foto não abre, o casco vira o
  estado de erro do board "Visualizador / erro": cartão calmo com "Tentar de
  novo" e "Falar com quem cuida", e a frase honesta "Não conseguimos abrir
  esta foto".

  Thumbnails: `/files/:id/thumbnail/sm` (grade) e `md` (visualizador), o
  worker `Rendition` gera depois do upload; enquanto não há thumbnail, o
  controller responde 404 e o quadradinho fica com o fundo de superfície.
  Vídeo não tem thumbnail: o tile mostra o marcador de play.
  """

  use TainaWeb, :live_view

  alias Taina.Jaci
  alias Taina.Ybira
  alias TainaWeb.InternalPath
  alias TainaWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:counts, nil)
     |> assign(:current, nil)
     |> assign(:grid_error, false)
     |> assign(:grid_stale, true)
     |> assign(:grid_zona, nil)
     |> assign(:last_group, nil)
     |> assign(:last_tab, :grid)
     |> assign(:loaded, false)
     |> assign(:next_cursor, nil)
     |> assign(:page_title, gettext("Galeria"))
     |> assign(:photo_ids, [])
     |> assign(:timeline_cursor, nil)
     |> assign(:timeline_empty, true)
     |> assign(:timeline_error, false)
     |> assign(:timeline_stale, true)
     |> assign(:timeline_zona, nil)
     |> assign(:viewer_error, false)
     |> assign(:viewer_rkey, nil)
     |> assign(:zona, :tudo)
     |> stream(:photos, [])
     |> stream_configure(:timeline_groups, dom_id: &timeline_dom_id/1)
     |> stream(:timeline_groups, [])}
  end

  @impl true
  def handle_params(params, uri, socket) do
    zona = parse_zona(params["zona"])
    return_to = InternalPath.from_uri(uri)

    case socket.assigns.live_action do
      :grid ->
        {:noreply,
         socket |> assign(:last_tab, :grid) |> assign(:return_to, return_to) |> assign(:zona, zona) |> ensure_grid()}

      :timeline ->
        {:noreply,
         socket
         |> assign(:last_tab, :timeline)
         |> assign(:return_to, return_to)
         |> assign(:zona, zona)
         |> ensure_timeline()}

      :viewer ->
        {:noreply, socket |> assign(:return_to, return_to) |> open_viewer(params["id"])}
    end
  end

  # Cada aba mantém seu cache de stream. No visualizador, só a aba de origem
  # fica montada, para preservar o scroll sem duplicar os dois fluxos no DOM.
  # Trocar de zona invalida o cache da aba e exige uma nova leitura.
  defp ensure_grid(%{assigns: %{grid_stale: false, grid_zona: zona, zona: zona}} = socket) do
    socket
    |> assign(:current, nil)
    |> assign(:timeline_stale, true)
  end

  defp ensure_grid(socket) do
    socket = assign(socket, :timeline_stale, true)

    case Jaci.list_photos(socket.assigns.current_scope, zona: zona_filter(socket.assigns.zona)) do
      {:ok, %{items: photos, next_cursor: cursor}} ->
        socket
        |> assign(:counts, media_count(socket))
        |> assign(:current, nil)
        |> assign(:grid_error, false)
        |> assign(:grid_stale, false)
        |> assign(:grid_zona, socket.assigns.zona)
        |> assign(:loaded, true)
        |> assign(:next_cursor, cursor)
        |> assign(:photo_ids, Enum.map(photos, & &1.rkey))
        |> stream(:photos, photos, reset: true)

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

    case Jaci.timeline(socket.assigns.current_scope, zona: zona_filter(socket.assigns.zona)) do
      {:ok, %{groups: groups, next_cursor: cursor}} ->
        socket
        |> assign(:counts, media_count(socket))
        |> assign(:current, nil)
        |> assign(:last_group, List.last(groups))
        |> assign(:photo_ids, timeline_photo_ids(groups))
        |> assign(:timeline_cursor, cursor)
        |> assign(:timeline_empty, groups == [])
        |> assign(:timeline_error, false)
        |> assign(:timeline_stale, false)
        |> assign(:timeline_zona, socket.assigns.zona)
        |> stream(:timeline_groups, groups, reset: true, dom_id: &timeline_dom_id/1)

      {:error, _reason} ->
        socket
        |> assign(:timeline_error, true)
        |> Phoenix.LiveView.put_flash(:error, gettext("Não foi possível carregar as fotos agora."))
    end
  end

  # Link direto para /galeria/:id (sem grade carregada): navega só esta foto.
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

  defp gallery_path(:grid, :tudo), do: ~p"/galeria"
  defp gallery_path(:grid, :praca), do: ~p"/galeria?#{[zona: "praca"]}"
  defp gallery_path(:grid, :casa), do: ~p"/galeria?#{[zona: "casa"]}"
  defp gallery_path(:timeline, :tudo), do: ~p"/galeria/linha-do-tempo"
  defp gallery_path(:timeline, :praca), do: ~p"/galeria/linha-do-tempo?#{[zona: "praca"]}"
  defp gallery_path(:timeline, :casa), do: ~p"/galeria/linha-do-tempo?#{[zona: "casa"]}"

  # "38 fotos, 4 vídeos" (board): o retrato do conjunto, vírgula como
  # separador (spec 1.6). O total vem do agregado (`Jaci.count_media/2`),
  # então a linha não depende de a grade ter carregado todas as páginas.
  defp grade_count(%{counts: %{fotos: fotos, videos: videos}}) when fotos + videos > 0 do
    # Parte zerada da linha do total não existe ("2 fotos" sem "0 vídeos").
    foto_part = if fotos == 0, do: nil, else: ngettext("1 foto", "%{count} fotos", fotos)
    video_part = if videos == 0, do: nil, else: ngettext("1 vídeo", "%{count} vídeos", videos)

    [foto_part, video_part]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  defp grade_count(_pagina_incompleta_ou_vazia), do: nil

  # "4 de outubro" (board): o dia escrito por extenso. O strftime não sabe
  # pt-BR sem locale, então o mês vem do mapa nosso.
  defp group_title(date) do
    gettext("%{day} de %{month}", day: date.day, month: month_name(date.month))
  end

  defp maybe_assign_new_ids(%{assigns: %{photo_ids: []}} = socket, rkey) do
    assign(socket, :photo_ids, [rkey])
  end

  defp maybe_assign_new_ids(socket, _rkey), do: socket

  # O total do conjunto para a linha do board: agregado no banco, com o
  # mesmo filtro de zona da grade. Falha de agregado não derruba a tela: a
  # linha cala em vez de mentir.
  defp media_count(socket) do
    case Jaci.count_media(socket.assigns.current_scope, zona: zona_filter(socket.assigns.zona)) do
      {:ok, counts} -> counts
      {:error, _reason} -> nil
    end
  end

  defp month_name(1), do: gettext("janeiro")
  defp month_name(2), do: gettext("fevereiro")
  defp month_name(3), do: gettext("março")
  defp month_name(4), do: gettext("abril")
  defp month_name(5), do: gettext("maio")
  defp month_name(6), do: gettext("junho")
  defp month_name(7), do: gettext("julho")
  defp month_name(8), do: gettext("agosto")
  defp month_name(9), do: gettext("setembro")
  defp month_name(10), do: gettext("outubro")
  defp month_name(11), do: gettext("novembro")
  defp month_name(12), do: gettext("dezembro")

  defp open_viewer(socket, rkey) do
    socket = assign(socket, :viewer_rkey, rkey)

    case Ybira.get_file(socket.assigns.current_scope, rkey) do
      {:ok, file} ->
        socket
        |> assign(:current, file)
        |> assign(:viewer_error, false)
        |> maybe_assign_new_ids(rkey)

      # Casa de outra pessoa: a tela de preview é quem explica o "Pedir
      # acesso"; aqui só levamos a pessoa até lá.
      {:error, :forbidden} ->
        Phoenix.LiveView.push_navigate(socket, to: ~p"/documentos/#{rkey}")

      # O board "Visualizador / erro": o casco do visualizador fica de pé com
      # o cartão calmo. O flash + volta automática antigos escondiam o erro.
      {:error, _reason} ->
        socket
        |> assign(:current, nil)
        |> assign(:viewer_error, true)
    end
  end

  # Zona na URL, como em Arquivos; a diferenca e o default: Fotos e a galeria
  # da comunidade (o conjunto legivel inteiro), entao sem parametro a aba e
  # Tudo. ?zona=casa e ?zona=praca estreitam a leitura; a abertura do upload
  # nunca "some", porque Tudo inclui a casa.
  defp parse_zona("praca"), do: :praca
  defp parse_zona("casa"), do: :casa
  defp parse_zona(_tudo_default), do: :tudo

  # O estado vazio diz a verdade sobre o que está sendo lido: o board desenha
  # o conjunto inteiro; ?zona= segue filtrando na URL, então as palavras da
  # casa e da praça continuam para quem chega por elas.
  defp photo_empty_copy(:tudo),
    do:
      {gettext("Ainda não há fotos"), gettext("Quando alguém enviar uma foto, ela aparece aqui para toda a comunidade.")}

  defp photo_empty_copy(:casa),
    do:
      {gettext("Nenhuma foto sua ainda"),
       gettext("As fotos que você enviar ficam aqui, na sua casa. Publique na praça para todos verem.")}

  defp photo_empty_copy(:praca),
    do: {gettext("A praça está vazia"), gettext("As fotos publicadas para a comunidade aparecem aqui.")}

  # Grade/timeline e visualizador usam cascas diferentes (spec 6): a casca
  # `service` só fora do `:viewer` (título e abas na casca, sem `<h1>` na tela;
  # spec 1.5) e a `viewer` fullscreen no `:viewer`. Toda a tela é uma função
  # componente pura, os mesmos assigns que o socket fornece (spec 1.3).
  defp service_tab(:grid), do: "grid"
  defp service_tab(:timeline), do: "timeline"

  defp step(socket, delta) do
    ids = socket.assigns.photo_ids
    current_id = socket.assigns.current && socket.assigns.current.rkey

    with index when is_integer(index) <- current_id && Enum.find_index(ids, &(&1 == current_id)),
         next_index = index + delta,
         true <- next_index >= 0 and next_index < length(ids) do
      Phoenix.LiveView.push_patch(socket, to: ~p"/galeria/#{Enum.at(ids, next_index)}")
    else
      _out_of_range -> socket
    end
  end

  # Um id por dia: o stream atualiza o grupo fundido no lugar em vez de
  # empilhar uma seção nova com o mesmo dia.
  defp timeline_dom_id(group), do: "timeline-group-#{group.date}"

  defp timeline_photo_ids(groups) do
    for group <- groups, photo <- group.photos, do: photo.rkey
  end

  @impl true
  def handle_event("load_more", _params, socket) do
    zona = zona_filter(socket.assigns.zona)

    case {socket.assigns.live_action, socket.assigns.next_cursor, socket.assigns.timeline_cursor} do
      {:grid, cursor, _t} when is_binary(cursor) ->
        case Jaci.list_photos(socket.assigns.current_scope, after_cursor: cursor, zona: zona) do
          {:ok, %{items: photos, next_cursor: next_cursor}} ->
            {:noreply,
             socket
             |> assign(:next_cursor, next_cursor)
             |> assign(:photo_ids, socket.assigns.photo_ids ++ Enum.map(photos, & &1.rkey))
             |> stream(:photos, photos)}

          {:error, _reason} ->
            {:noreply, Phoenix.LiveView.put_flash(socket, :error, gettext("Não foi possível carregar mais fotos agora."))}
        end

      {:timeline, _g, cursor} when is_binary(cursor) ->
        case Jaci.timeline(socket.assigns.current_scope, after_cursor: cursor, zona: zona) do
          {:ok, %{groups: groups, next_cursor: next_cursor}} ->
            {last_group, stream_page} = extend_timeline(socket.assigns.last_group, groups)

            {:noreply,
             socket
             |> assign(:last_group, last_group)
             |> assign(:photo_ids, socket.assigns.photo_ids ++ timeline_photo_ids(groups))
             |> assign(:timeline_cursor, next_cursor)
             |> stream(:timeline_groups, stream_page, dom_id: &timeline_dom_id/1)}

          {:error, _reason} ->
            {:noreply, Phoenix.LiveView.put_flash(socket, :error, gettext("Não foi possível carregar mais fotos agora."))}
        end

      _other ->
        {:noreply, socket}
    end
  end

  # Setas e Escape do visualizador: o board não tem barra de ações nem
  # sobreposição, então a navegação é direta.
  def handle_event("prev", _params, socket), do: {:noreply, step(socket, -1)}
  def handle_event("next", _params, socket), do: {:noreply, step(socket, +1)}

  def handle_event("close", _params, socket) do
    {:noreply, Phoenix.LiveView.push_patch(socket, to: gallery_path(socket.assigns.last_tab, socket.assigns.zona))}
  end

  def handle_event("retry", _params, socket) do
    case socket.assigns.live_action do
      :grid -> {:noreply, ensure_grid(socket)}
      :timeline -> {:noreply, ensure_timeline(socket)}
      # No estado de erro do visualizador, "Tentar de novo" é reabrir a foto.
      :viewer -> {:noreply, open_viewer(socket, socket.assigns.viewer_rkey)}
    end
  end

  # "Falar com quem cuida" (segunda saída do cartão de erro): a Saúde é a tela
  # que diz quem cuida da máquina. Web não abre conversa com ninguém.
  def handle_event("contact", _params, socket) do
    {:noreply, Phoenix.LiveView.push_navigate(socket, to: ~p"/saude")}
  end

  # --- zonas casa/praca (RFC_003 D1/D2) ---

  defp upload_path(return_to), do: ~p"/documentos/enviar?#{[return_to: return_to]}"

  defp video?(%{mime: mime}), do: String.starts_with?(mime, "video/")

  # "3 de 24" (board): a posição na trilha que a tela já carrega. Sem trilha
  # (link direto que falhou), a linha cala em vez de inventar "1 de 1".
  defp viewer_counter(ids, id) do
    case Enum.find_index(ids, &(&1 == id)) do
      nil -> nil
      index -> gettext("%{index} de %{total}", index: index + 1, total: length(ids))
    end
  end

  # A zona na consulta (Jaci filtra no SQL): o cursor caminha no conjunto
  # filtrado, e a aba de zona recebe paginas completas.
  defp zona_filter(:tudo), do: nil
  defp zona_filter(zona), do: zona

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :gallery, assigns)

    ~H"""
    <Layouts.service
      :if={@live_action != :viewer}
      flash={@flash}
      service="jaci"
      current={service_tab(@live_action)}
      title={@page_title}
      back={~p"/"}
    >
      <:actions>
        <.button kind="primary" size="md" class="hide-mobile" navigate={upload_path(@return_to)}>
          {gettext("Enviar")}
        </.button>
      </:actions>
      <:fab>
        <.fab label={gettext("Enviar")} navigate={upload_path(@return_to)} />
      </:fab>

      <.gallery_content g={@gallery} />
    </Layouts.service>

    <Layouts.viewer :if={@live_action == :viewer} flash={@flash}>
      <.gallery_content g={@gallery} />
    </Layouts.viewer>
    """
  end

  @doc """
  Corpo da Galeria: componente puro, recebe os assigns da tela e devolve HEEx.
  É aqui que cada estado dos boards escolhe a sua branch: grade, linha do
  tempo, visualizador e o visualizador de erro (spec 1.3).
  """
  attr :g, :map,
    required: true,
    doc: "assigns da tela"

  def gallery_content(assigns) do
    assigns =
      assigns
      |> assign(:g, Map.put_new(assigns.g, :return_to, ~p"/galeria"))
      |> assign(:grade_count, grade_count(assigns.g))
      |> assign(:viewer_counter, viewer_counter(assigns.g.photo_ids, assigns.g.viewer_rkey))

    ~H"""
    <div :if={@g.live_action == :grid or (@g.live_action == :viewer and @g.last_tab == :grid)} class="mt-4">
      <.skeleton :if={not @g.loaded} kind="photo_grid" count={12} />

      <p :if={@grade_count} class="type-caption text-muted mb-2">{@grade_count}</p>

      <div :if={@g.loaded} id="photo-grid" class="photo-grid" phx-update="stream">
        <.link
          :for={{dom_id, photo} <- @g.streams.photos}
          id={dom_id}
          patch={~p"/galeria/#{photo.rkey}"}
          class="photo-grid__item"
          aria-label={photo.nome}
        >
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

      <div :if={@g.loaded && @g.next_cursor} id="grid-load-more" phx-viewport-bottom="load_more" class="mt-4">
        <.skeleton kind="photo_grid" count={6} />
      </div>

      <% {empty_title, empty_hint} = photo_empty_copy(@g.zona) %>

      <.empty_state
        :if={@g.loaded && @g.photo_ids == [] and not @g.grid_error}
        icon="image"
        title={empty_title}
        body={empty_hint}
      >
        <:action>
          <.button kind="primary" size="md" navigate={upload_path(@g.return_to)}>
            {gettext("Enviar uma foto")}
          </.button>
        </:action>
      </.empty_state>

      <.empty_state
        :if={@g.grid_error}
        icon="alert"
        title={gettext("Não foi possível carregar")}
        body={gettext("As fotos não responderam agora.")}
      >
        <:action>
          <.button kind="secondary" phx-click="retry">{gettext("Tentar de novo")}</.button>
        </:action>
      </.empty_state>
    </div>

    <div :if={@g.live_action == :timeline or (@g.live_action == :viewer and @g.last_tab == :timeline)} class="mt-4 col gap-5">
      <div id="timeline-groups" phx-update="stream" class="col gap-5">
        <section :for={{dom_id, group} <- @g.streams.timeline_groups} id={dom_id}>
          <h2 class="type-h3 mb-2">
            {group_title(group.date)}
          </h2>
          <div class="photo-grid photo-grid--timeline">
            <.link
              :for={photo <- group.photos}
              patch={~p"/galeria/#{photo.rkey}"}
              class="photo-grid__item"
              aria-label={photo.nome}
            >
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

      <div :if={@g.timeline_cursor} id="timeline-load-more" phx-viewport-bottom="load_more">
        <.skeleton kind="photo_grid" count={6} />
      </div>

      <% {empty_title, empty_hint} = photo_empty_copy(@g.zona) %>

      <.empty_state
        :if={@g.live_action == :timeline and @g.timeline_empty and not @g.timeline_error}
        icon="image"
        title={empty_title}
        body={empty_hint}
      >
        <:action>
          <.button kind="primary" size="md" navigate={upload_path(@g.return_to)}>
            {gettext("Enviar uma foto")}
          </.button>
        </:action>
      </.empty_state>

      <.empty_state
        :if={@g.live_action == :timeline and @g.timeline_error}
        icon="alert"
        title={gettext("Não foi possível carregar")}
        body={gettext("As fotos não responderam agora.")}
      >
        <:action>
          <.button kind="secondary" phx-click="retry">{gettext("Tentar de novo")}</.button>
        </:action>
      </.empty_state>
    </div>

    <.viewer
      :if={@g.current}
      file={@g.current}
      photo_ids={@g.photo_ids}
      zona={@g.current.zona}
      link={url(~p"/files/#{@g.current.rkey}")}
      src={~p"/files/#{@g.current.rkey}"}
      src_md={~p"/files/#{@g.current.rkey}/thumbnail/md"}
    />

    <div
      :if={@g.viewer_error && @g.live_action == :viewer}
      id="viewer"
      class="viewer"
      role="dialog"
      aria-modal="true"
      aria-label={gettext("Visualizador de fotos")}
      phx-hook="ViewerNav"
    >
      <header class="row between p-4">
        <.icon_button name="close" label={gettext("Fechar")} id="viewer-close" phx-click="close" />
      </header>

      <div class="viewer__stage">
        <.error_card
          title={gettext("Não conseguimos falar com a nuvem agora.")}
          retry_event="retry"
          contact_event="contact"
        />
      </div>

      <div class="viewer__caption row between gap-3">
        <span class="truncate">{gettext("Não conseguimos abrir esta foto")}</span>
        <span :if={@viewer_counter} class="text-muted">{@viewer_counter}</span>
      </div>
    </div>

    """
  end
end
