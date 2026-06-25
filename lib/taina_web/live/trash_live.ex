defmodule TainaWeb.TrashLive do
  @moduledoc """
  Lixeira (tela "Ybira - Lixeira"): itens apagados nos últimos 30 dias, com
  restauração. A purga definitiva é automática (`PurgeTrash`, Oban, 30 dias),
  o design mostra exclusão definitiva por item, mas o Ybira ainda não expõe
  essa operação; fica para quando o context ganhar `purge_file/2`.
  """

  use TainaWeb, :live_view

  alias Taina.Ybira
  alias TainaWeb.Layouts

  @retention_days 30
  @warning_days 5

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, gettext("Lixeira")) |> load_trash()}
  end

  defp load_trash(socket) do
    {:ok, %{items: items, next_cursor: next_cursor}} = Ybira.list_trash(socket.assigns.current_scope)

    socket
    |> assign(:items, items)
    |> assign(:next_cursor, next_cursor)
  end

  @impl true
  def handle_event("restore", %{"id" => public_id}, socket) do
    case Ybira.restore_file(socket.assigns.current_scope, public_id) do
      {:ok, _file} ->
        {:noreply,
         socket
         |> Phoenix.LiveView.put_flash(:info, gettext("Arquivo restaurado."))
         |> load_trash()}

      {:error, _reason} ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, gettext("Não foi possível restaurar o arquivo."))}
    end
  end

  def handle_event("load-more", _params, socket) do
    if cursor = socket.assigns.next_cursor do
      {:ok, %{items: items, next_cursor: next_cursor}} =
        Ybira.list_trash(socket.assigns.current_scope, after_cursor: cursor)

      {:noreply,
       socket
       |> assign(:items, socket.assigns.items ++ items)
       |> assign(:next_cursor, next_cursor)}
    else
      {:noreply, socket}
    end
  end

  defp days_left(file) do
    deleted_days_ago = Date.diff(Date.utc_today(), DateTime.to_date(file.deleted_at))
    max(@retention_days - deleted_days_ago, 0)
  end

  defp trash_meta(file) do
    left = days_left(file)
    deleted_days = Date.diff(Date.utc_today(), DateTime.to_date(file.deleted_at))

    deleted_label =
      case deleted_days do
        0 -> gettext("Apagado hoje")
        1 -> gettext("Apagado ontem")
        days -> gettext("Apagado há %{count} dias", count: days)
      end

    if left <= @warning_days do
      ngettext("Resta %{count} dia, apaga em breve", "Restam %{count} dias, apaga em breve", left)
    else
      deleted_label <> ", " <> ngettext("resta %{count} dia", "restam %{count} dias", left)
    end
  end

  defp warning?(file), do: days_left(file) <= @warning_days

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active_tab={:files}
      storage_stats={assigns[:storage_stats]}
      account_alert={assigns[:account_alert] || false}
    >
      <Layouts.app_bar title={gettext("Lixeira")} back={~p"/arquivos"} />

      <div class="col gap-4 mx-auto w-full measure">
        <.card class="row gap-3">
          <.icon name="clock" size={20} class="text-warning" />
          <p class="type-body-sm text-secondary">
            {gettext("Itens são apagados para sempre após %{count} dias na lixeira.", count: 30)}
          </p>
        </.card>

        <p class="type-overline text-faint">
          {ngettext("%{count} item", "%{count} itens", length(@items))}
        </p>

        <div class="list">
          <.list_row
            :for={file <- @items}
            title={file.original_filename}
            meta={trash_meta(file)}
            meta_class={warning?(file) && "text-warning"}
          >
            <:leading>
              <% {_service, icon} = file_visual(file.mime_type) %>
              <.service_square service="neutral" icon={icon} />
            </:leading>
            <:actions>
              <.icon_button
                name="restore"
                label={gettext("Restaurar")}
                phx-click="restore"
                phx-value-id={file.public_id}
              />
            </:actions>
          </.list_row>
        </div>

        <div :if={@next_cursor} id="trash-load-more" phx-viewport-bottom="load-more" class="center py-4">
          <p class="type-caption text-faint">{gettext("Carregando mais...")}</p>
        </div>

        <.empty_state
          :if={@items == []}
          icon="trash"
          title={gettext("Lixeira vazia")}
          hint={gettext("Nada esperando para ser apagado.")}
        />
      </div>
    </Layouts.app>
    """
  end
end
