defmodule TainaWeb.HomeLive do
  @moduledoc """
  Home "superapp": saudação, cartão de armazenamento, cards de serviço
  (Arquivos/Fotos/Membros e Mensagens "em breve") e os envios recentes.
  Tela "Home - Superapp" (mobile) e "Desktop - Home" do Penpot.
  """

  use TainaWeb, :live_view

  alias Taina.Ybira
  alias TainaWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok, recent} = Ybira.list_recent(scope, limit: 4)
    {:ok, by_kind} = Ybira.storage_stats_by_kind(scope)

    {:ok,
     socket
     |> assign(:page_title, gettext("Início"))
     |> assign(:recent, recent)
     |> assign(:by_kind, by_kind)}
  end

  # Saudação pelo relógio da caixa, o servidor mora na casa da comunidade,
  # então o horário local do sistema é o horário local de quem usa.
  defp greeting do
    {_date, {hour, _min, _sec}} = :calendar.local_time()

    cond do
      hour in 5..11 -> gettext("Bom dia,")
      hour in 12..17 -> gettext("Boa tarde,")
      true -> gettext("Boa noite,")
    end
  end

  defp segments(by_kind, %{used_bytes: used}) when used > 0 do
    for {kind, bytes} <- Enum.sort_by(by_kind, fn {_k, b} -> -b end), bytes > 0 do
      {Atom.to_string(kind), bytes / used}
    end
  end

  defp segments(_by_kind, _stats), do: []

  defp recent_meta(file) do
    "#{file_kind(file.mime_type)}, #{format_bytes(file.file_size_bytes)}, #{relative_time(file.inserted_at)}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active_tab={:home}
      storage_stats={assigns[:storage_stats]}
    >
      <div class="row between mb-6">
        <div>
          <p class="type-body text-secondary">{greeting()}</p>
          <h1 class="type-h1">{@current_scope.tekoa.name}</h1>
        </div>
        <.avatar name={@current_scope.ava.username || @current_scope.ava.email} />
      </div>

      <.card :if={@storage_stats} class="mb-6">
        <div class="row between mb-3">
          <p class="type-label">{gettext("Armazenamento")}</p>
          <p :if={@storage_stats.quota_bytes} class="type-caption text-success">
            {format_bytes(@storage_stats.quota_bytes - @storage_stats.used_bytes)} {gettext("livres")}
          </p>
        </div>
        <.progress :if={segments(@by_kind, @storage_stats) != []} segments={segments(@by_kind, @storage_stats)} />
        <.progress :if={segments(@by_kind, @storage_stats) == []} value={0} />
        <p class="type-caption text-muted mt-3">
          {gettext("%{used} de %{total} usados",
            used: format_bytes(@storage_stats.used_bytes),
            total: format_bytes(@storage_stats.quota_bytes)
          )}
        </p>
      </.card>

      <p class="type-overline text-faint mb-3">{gettext("Recentes")}</p>
      <div class="list">
        <.list_row
          :for={file <- @recent}
          title={file.original_filename}
          meta={recent_meta(file)}
          navigate={~p"/arquivos/#{file.public_id}"}
        >
          <:leading>
            <% {service, icon} = file_visual(file.mime_type) %>
            <.service_square service={service} icon={icon} />
          </:leading>
          <:actions>
            <.icon name="chevron-right" size={18} class="text-faint" />
          </:actions>
        </.list_row>
      </div>

      <.empty_state
        :if={@recent == []}
        icon="upload"
        title={gettext("Nada por aqui ainda")}
        hint={gettext("Envie o primeiro arquivo da comunidade.")}
      >
        <.button variant="primary" size="md" navigate={~p"/arquivos/enviar"}>
          {gettext("Enviar arquivos")}
        </.button>
      </.empty_state>
    </Layouts.app>
    """
  end
end
