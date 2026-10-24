defmodule TainaWeb.UI.Media do
  @moduledoc """
  Mídia do design system (Penpot, "01 - Componentes"), um `function
  component` por linha da tabela (docs/web-revamp-spec.md, 4.1):

  | Nome | Board id |
  | --- | --- |
  | Viewer | 3fd18cd2-90f8-80f3-8008-d5c33aeff2fa |
  | Dropzone | 3fd18cd2-90f8-80f3-8008-d5c43451b694 |

  O `upload_row` do spec (2.1) NÃO é um componente: é a composição
  `<.list_row kind="upload">` (UI.Content) que as telas de upload montam com
  `:leading`/`:actions`. Importado pelas telas via `html_helpers`.
  """

  use Phoenix.Component
  use Gettext, backend: TainaWeb.Gettext

  use Phoenix.VerifiedRoutes,
    endpoint: TainaWeb.Endpoint,
    router: TainaWeb.Router,
    statics: ~w(assets fonts icons robots.txt favicon.ico openapi.yaml)

  import TainaWeb.CoreComponents, only: [format_bytes: 1]

  # ---------- Viewer ----------

  import TainaWeb.Icons
  import TainaWeb.UI.Actions, only: [icon_button: 1, button: 1]
  import TainaWeb.UI.Content, only: [progress: 1]

  @doc """
  Visualizador fullscreen (Penpot: Viewer, 3fd18cd2-90f8-80f3-8008-d5c33aeff2fa):
  markup movido da Galeria (comportamento idêntico, `ViewerNav` e `FullSwap`
  preservados). Projetado coberta da tela com `role="dialog"`; navegação por
  teclado/swipe fica no hook; o servidor decide (eventos `prev`/`next`/
  `close`/`ask-zona`/`ask-details`/`toggle-details`/`ask-delete` da tela).

  Os caminhos (arquivo, thumb `md`, link absoluto do Clipboard/Share, a
  trilha de fotos vizinhas) são construídos pela tela com `~p`/`url` -
  nada de URL mágica aqui.

      <.viewer
        :if={@current}
        file={@current}
        photo_ids={@photo_ids}
        own={own?(@current_scope, @current)}
        zona={@current.zona}
        link={url(~p"/files/\#{@current.rkey}")}
        src={~p"/files/\#{@current.rkey}"}
        src_md={~p"/files/\#{@current.rkey}/thumbnail/md"}
        rail={viewer_rail(@photo_ids, @current.rkey)}
      />
  """
  attr :file, :any, required: true, doc: "arquivo Ybira da foto atual (nome, mime, tamanho, inserted_at)"
  attr :photo_ids, :list, default: [], doc: "rkeys da sequência atual (grade ou linha inteira)"
  attr :own, :boolean, default: false, doc: "alavanca da zona só para quem é dono"
  attr :zona, :atom, required: true, values: [:casa, :praca]
  attr :link, :string, required: true, doc: "URL absoluta do arquivo original (Clipboard/Share)"
  attr :src, :string, required: true, doc: "URL do original (download/video)"
  attr :src_md, :string, required: true, doc: "URL da rendição md (viewer carrega ela primeiro)"
  attr :rail, :list, default: [], doc: "fotos vizinhas (viewer_rail/2): %{id:, position:, thumb:, patch:}"
  attr :rest, :global

  def viewer(assigns) do
    ~H"""
    <div
      id="viewer"
      class="viewer"
      role="dialog"
      aria-modal="true"
      aria-label={gettext("Visualizador de fotos")}
      phx-hook="ViewerNav"
      {@rest}
    >
      <header class="row between p-4">
        <.icon_button name="close" label={gettext("Fechar")} id="viewer-close" phx-click="close" />
        <div class="text-center">
          <p class="type-label">{photo_date(@file)}</p>
          <p class="type-caption text-faint">
            {gettext("%{index} de %{total}", index: viewer_index(@photo_ids, @file), total: length(@photo_ids))}
          </p>
        </div>
        <.icon_button
          name="link"
          label={gettext("Copiar link")}
          id="viewer-copy-link"
          phx-hook="Clipboard"
          data-copy={@link}
        />
      </header>

      <div class="viewer__stage">
        <video
          :if={video?(@file)}
          controls
          preload="metadata"
          playsinline
          src={@src}
        ></video>
        <img
          :if={!video?(@file)}
          id="viewer-full-swap"
          phx-hook="FullSwap"
          src={@src_md}
          data-full={full_swap?(@file) && @link}
          alt={@file.nome}
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
          :for={photo <- @rail}
          id={"rail-#{photo.id}"}
          patch={photo.patch}
          class="viewer__rail-item"
          aria-current={photo.id == @file.rkey}
          aria-label={gettext("Foto %{index} de %{total}", index: photo.position, total: length(@photo_ids))}
        >
          <span class="viewer__rail-thumb" style={"background-image: url('#{photo.thumb}')"}></span>
        </.link>
      </nav>

      <p class="viewer__caption">{@file.nome}</p>

      <div class="viewer__actions">
        <button
          type="button"
          class="viewer__action"
          id="viewer-share"
          phx-hook="Share"
          data-url={@link}
          data-title={@file.nome}
        >
          <.icon name="share" size={20} />
          <span>{gettext("Compartilhar")}</span>
        </button>
        <a href={@src} download class="viewer__action">
          <.icon name="download" size={20} />
          <span>{gettext("Baixar")}</span>
        </a>
        <button
          :if={@own}
          type="button"
          class="viewer__action"
          phx-click="ask-zona"
        >
          <.icon name="eye" size={20} />
          <span>{zona_action_label(@zona)}</span>
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
    """
  end

  # Janela de fotos vizinhas da barra do viewer (desktop 1024+): um trecho
  # curto em volta da atual (`@rail_window` de cada lado), mapas de
  # `{id:, posição, thumb, patch}` com o caminho pronto, para o rótulo
  # acessível de cada miniatura e o link de troca. Puro, testável sem socket.
  @rail_window 10

  def viewer_rail(ids, current_id) do
    case Enum.find_index(ids, &(&1 == current_id)) do
      nil ->
        []

      index ->
        first = max(index - @rail_window, 0)
        last = min(index + @rail_window, length(ids) - 1)

        for i <- first..last do
          id = Enum.at(ids, i)

          %{
            id: id,
            position: i + 1,
            thumb: ~p"/files/#{id}/thumbnail/sm",
            patch: ~p"/galeria/#{id}"
          }
        end
    end
  end

  # A data do visualizador vem do upload (o kernel nao carrega os metadados
  # de rendicao); a linha do tempo agrupa pela data efetiva, resolvida na
  # consulta do Jaci.
  defp photo_date(file) do
    file.inserted_at
    |> NaiveDateTime.to_date()
    |> Calendar.strftime("%d/%m/%Y")
  end

  # ---------- Dropzone ----------

  defp viewer_index(ids, %{rkey: id}), do: (Enum.find_index(ids, &(&1 == id)) || 0) + 1

  defp video?(%{mime: mime}), do: String.starts_with?(mime, "video/")

  # Troca progressiva: o `md` carrega primeiro e o original entra por baixo
  # (hook `FullSwap`), só quando o tamanho cabe no orçamento do Pi; arquivo
  # demais trava a caixa por causa de um preview.
  @full_swap_cap_bytes 20 * 1024 * 1024

  defp full_swap?(%{tamanho: bytes}), do: bytes <= @full_swap_cap_bytes

  # A acao oferecida e sempre a oposta da zona atual (consentimento,
  # RFC_003): a casa publica na praça; a praça volta para a casa.
  defp zona_action_label(:casa), do: gettext("Publicar na praça")
  defp zona_action_label(:praca), do: gettext("Tirar da praça")

  @doc """
  Caixa de envio (Penpot: Dropzone, State idle/drag/uploading/error-cota/
  error-rede, 3fd18cd2-90f8-80f3-8008-d5c43451b694). Estado idle é o <label>
  tocável (input `sr-only`, drop por `phx-drop-target`); o realce de arrasto
  é o modificador `--drag`, trocado pelo hook `DragClass`; os demais estados
  são estados de tela (nada de máquina aqui), o picker continua no DOM
  (sr-only) em todos os estados. "X de Y" do uploading é o
  arquivo corrente (o `client_size` dele e a % já do LiveView), não a fila
  inteira.

  A tela decide:
      <.dropzone id="dropzone" upload={@uploads.files} state={dropzone_state(@uploads)} class="w-full" />

  Erros (cota/rede) entram com os ganchos prontos:
      <.dropzone state="error-cota" error_href={~p"/armazenamento"} />
      <.dropzone state="error-rede" retry="retry" />
  """
  attr :upload, :any, required: true, doc: "o campo do LiveView (@uploads.files)"

  attr :state, :string,
    default: "idle",
    values: ~w(idle drag uploading error-cota error-rede),
    doc: "State do Penpot; `drag` é a classe trocada pelo hook DragClass"

  attr :error_href, :string, default: nil, doc: "destino do Ver espaço (state error-cota)"
  attr :retry, :any, default: nil, doc: "evento/JS do Tentar de novo (state error-rede)"
  attr :rest, :global

  def dropzone(%{state: "idle"} = assigns) do
    ~H"""
    <label class="dropzone" phx-drop-target={@upload.ref} phx-hook="DragClass" {@rest}>
      <.icon name="upload" size={28} />
      <span class="dropzone__title dropzone__title--idle">{gettext("Toque para escolher")}</span>
      <span class="dropzone__title dropzone__title--drag">{gettext("Solte para enviar")}</span>
      <span class="dropzone__hint">
        {gettext("Ou arraste os arquivos. Vai para a casa: só entra quem você deixar.")}
      </span>
      <span class="dropzone__cta">{gettext("Escolher arquivos")}</span>
      <.live_file_input upload={@upload} class="sr-only" />
    </label>
    """
  end

  def dropzone(%{state: "uploading"} = assigns) do
    assigns = assign(assigns, :entry, entry(assigns.upload))

    ~H"""
    <div class={["dropzone", "dropzone--uploading"]} {@rest}>
      <p class="dropzone__title dropzone__title--uploading">
        {gettext("Enviando %{name}", name: @entry.client_name)}
      </p>
      <p class="dropzone__percent">{@entry.progress}%</p>
      <.progress value={@entry.progress} label={gettext("Enviando %{name}", name: @entry.client_name)} />
      <p class="dropzone__help">
        {gettext("Guardando na casa. %{done} de %{total}",
          done: format_bytes(done_bytes(@entry)),
          total: format_bytes(@entry.client_size)
        )}
      </p>
      <.live_file_input upload={@upload} class="sr-only" />
    </div>
    """
  end

  def dropzone(%{state: state} = assigns) when state in ~w(error-cota error-rede) do
    ~H"""
    <div class={["dropzone", "dropzone--#{@state}"]} {@rest}>
      <.icon name="close" size={24} />
      <p class="dropzone__title">{gettext("Não deu para enviar")}</p>
      <p class="dropzone__help">{error_help(@state)}</p>
      <.button :if={@error_href} kind="secondary" size="md" navigate={@error_href}>
        {gettext("Ver espaço")}
      </.button>
      <.button :if={@retry} kind="secondary" size="md" phx-click={@retry}>
        {gettext("Tentar de novo")}
      </.button>
    </div>
    """
  end

  # A fila tem a entrada corrente (auto_upload consome quando termina);
  # primeiro empurrão visível.
  defp entry(upload) do
    case upload.entries do
      [entry | _] -> entry
      _ -> nil
    end
  end

  defp done_bytes(%{client_size: size, progress: pct}), do: div(size * pct, 100)
  defp done_bytes(_entry), do: 0

  # Copy do board Ver espaço (cota) e Tentar de novo (rede).
  defp error_help("error-cota"), do: gettext("O espaço da comunidade acabou. Peça a quem cuida da nuvem para liberar.")

  defp error_help("error-rede"), do: gettext("A conexão caiu no meio do envio. O arquivo não saiu da sua casa.")

  defp error_help(_state), do: nil
end
