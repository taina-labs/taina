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
  a foto ocupa a tela, com fechar, anterior/próxima e a legenda do board
  ("Nome, data, na praça" + "3 de 24"). `ViewerNav` cuida de teclado/swipe;
  o servidor decide (eventos `prev`/`next`/`close` da tela).

  O board não tem barra de ações no visualizador: baixar, publicar e remover
  moram na tela do documento (`/documentos/:id`), que é o mesmo arquivo com
  os controles por extenso.

  Os caminhos (arquivo, thumb `md`, link do FullSwap) são construídos pela
  tela com `~p`/`url` - nada de URL mágica aqui.

      <.viewer
        :if={@current}
        file={@current}
        photo_ids={@photo_ids}
        zona={@current.zona}
        link={url(~p"/files/\#{@current.rkey}")}
        src={~p"/files/\#{@current.rkey}"}
        src_md={~p"/files/\#{@current.rkey}/thumbnail/md"}
      />
  """
  attr :file, :any, required: true, doc: "arquivo Ybira da foto atual (nome, mime, tamanho, inserted_at)"
  attr :photo_ids, :list, default: [], doc: "rkeys da sequência atual (grade ou linha inteira)"
  attr :zona, :atom, required: true, values: [:casa, :praca]
  attr :link, :string, required: true, doc: "URL absoluta do arquivo original (FullSwap)"
  attr :src, :string, required: true, doc: "URL do original (vídeo)"
  attr :src_md, :string, required: true, doc: "URL da rendição md (viewer carrega ela primeiro)"
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
      <header class="row p-4">
        <.icon_button name="close" label={gettext("Fechar")} id="viewer-close" phx-click="close" />
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
          class="viewer__nav viewer__nav--prev"
          phx-click="prev"
          aria-label={gettext("Foto anterior")}
        >
          <.icon name="chevron-left" size={28} />
        </button>
        <button
          :if={length(@photo_ids) > 1}
          type="button"
          class="viewer__nav viewer__nav--next"
          phx-click="next"
          aria-label={gettext("Próxima foto")}
        >
          <.icon name="chevron-right" size={28} />
        </button>
      </div>

      <div class="viewer__caption row between gap-3">
        <span class="truncate">{viewer_caption(@file, @zona)}</span>
        <span class="text-faint">
          {gettext("%{index} de %{total}", index: viewer_index(@photo_ids, @file), total: length(@photo_ids))}
        </span>
      </div>
    </div>
    """
  end

  # Legenda do board: "Nome, 12/06/2026, na praça".
  defp viewer_caption(file, zona) do
    "#{file.nome}, #{photo_date(file)}, #{viewer_zona(zona)}"
  end

  defp viewer_zona(:praca), do: gettext("na praça")
  defp viewer_zona(:casa), do: gettext("na casa")

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
