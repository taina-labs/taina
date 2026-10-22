defmodule TainaWeb.TrashLive do
  @moduledoc """
  Lixeira (tela "Ybira - Lixeira"): arquivos e pastas apagados nos últimos 30
  dias, com restauração (a pasta volta como unidade, com o que foi apagado
  junto). A purga definitiva é automática (`PurgeTrash`, Oban, 30 dias), o
  design mostra exclusão definitiva por item, mas o Ybira ainda não expõe
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
    scope = socket.assigns.current_scope

    with {:ok, %{items: items, next_cursor: next_cursor}} <- Ybira.list_trash(scope),
         {:ok, folders} <- Ybira.list_trash_folders(scope) do
      socket
      |> assign(:items, items)
      |> assign(:folders, folders)
      |> assign(:next_cursor, next_cursor)
      |> assign(:load_error, false)
    else
      _error ->
        # Sem beco sem saída: flash com o que houve, e a lixeira vazia com a
        # saída ("Tentar de novo").
        socket
        |> assign(:items, [])
        |> assign(:folders, [])
        |> assign(:next_cursor, nil)
        |> assign(:load_error, true)
        |> Phoenix.LiveView.put_flash(:error, gettext("Não foi possível carregar a lixeira."))
    end
  end

  @impl true
  def handle_event("retry-load", _params, socket), do: {:noreply, load_trash(socket)}

  def handle_event("restore", %{"id" => rkey, "type" => "folder"}, socket) do
    case Ybira.restore_folder(socket.assigns.current_scope, rkey) do
      {:ok, _folder} ->
        {:noreply,
         socket
         |> Phoenix.LiveView.put_flash(:info, gettext("Pasta restaurada com o que tinha dentro."))
         |> load_trash()}

      {:error, _reason} ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, gettext("Não foi possível restaurar a pasta."))}
    end
  end

  def handle_event("restore", %{"id" => rkey}, socket) do
    case Ybira.restore_file(socket.assigns.current_scope, rkey) do
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
      case Ybira.list_trash(socket.assigns.current_scope, after_cursor: cursor) do
        {:ok, %{items: items, next_cursor: next_cursor}} ->
          {:noreply,
           socket
           |> assign(:items, socket.assigns.items ++ items)
           |> assign(:next_cursor, next_cursor)}

        {:error, _reason} ->
          {:noreply, Phoenix.LiveView.put_flash(socket, :error, gettext("Não foi possível carregar mais itens."))}
      end
    else
      {:noreply, socket}
    end
  end

  defp days_left(file) do
    deleted_days_ago = Date.diff(Date.utc_today(), DateTime.to_date(file.apagado_em))
    max(@retention_days - deleted_days_ago, 0)
  end

  defp trash_meta(file) do
    left = days_left(file)
    deleted_days = Date.diff(Date.utc_today(), DateTime.to_date(file.apagado_em))

    deleted_label =
      case deleted_days do
        0 -> gettext("Apagado hoje")
        1 -> gettext("Apagado ontem")
        days -> gettext("Apagado há %{count} dias", count: days)
      end

    meta =
      cond do
        left == 0 ->
          gettext("Apaga hoje")

        left <= @warning_days ->
          ngettext("Resta %{count} dia, apaga em breve", "Restam %{count} dias, apaga em breve", left)

        true ->
          deleted_label <> ", " <> ngettext("resta %{count} dia", "restam %{count} dias", left)
      end

    meta <> " / " <> readability_short(file.zona)
  end

  defp warning?(file), do: days_left(file) <= @warning_days

  # A regra da lixeira em texto, com o mesmo número que o worker usa para
  # expurgar. Função (não assign) porque `@retention_days` no template viria
  # de `assigns`, não do módulo.
  defp retention_line do
    gettext("Itens são apagados para sempre após %{count} dias na lixeira.", count: @retention_days)
  end

  # Versão curta da zona, igual à do navegador de arquivos: a meta trunca, a
  # zona não pode ser a parte que fica de fora.
  defp readability_short(:praca), do: gettext("Todos veem")
  defp readability_short(:casa), do: gettext("Só você")

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
          <p class="type-body-sm text-secondary">{retention_line()}</p>
        </.card>

        <p class="type-overline text-muted">
          <%= if @next_cursor do %>
            {ngettext("%{count} item carregado", "%{count} itens carregados", length(@folders) + length(@items))}
          <% else %>
            {ngettext("%{count} item", "%{count} itens", length(@folders) + length(@items))}
          <% end %>
        </p>

        <ul class="list">
          <.list_row
            :for={folder <- @folders}
            title={folder.nome}
            meta={trash_meta(folder)}
            meta_class={warning?(folder) && "text-warning"}
          >
            <:leading>
              <.service_square service="ybira" icon="folder" />
            </:leading>
            <:actions>
              <.icon_button
                name="restore"
                label={gettext("Restaurar")}
                phx-click="restore"
                phx-value-id={folder.rkey}
                phx-value-type="folder"
              />
            </:actions>
          </.list_row>

          <.list_row
            :for={file <- @items}
            title={file.nome}
            meta={trash_meta(file)}
            meta_class={warning?(file) && "text-warning"}
          >
            <:leading>
              <% {_service, icon} = file_visual(file.mime) %>
              <.service_square service="neutral" icon={icon} />
            </:leading>
            <:actions>
              <.icon_button
                name="restore"
                label={gettext("Restaurar")}
                phx-click="restore"
                phx-value-id={file.rkey}
                phx-value-type="file"
              />
            </:actions>
          </.list_row>
        </ul>

        <div :if={@next_cursor} id="trash-load-more" phx-viewport-bottom="load-more" class="list-row" aria-hidden="true">
          <span class="service-square service-square--neutral skeleton"></span>
          <span class="skeleton flex-1" style="height: var(--space-4);"></span>
        </div>

        <.empty_state
          :if={@items == [] and @folders == [] and @load_error}
          icon="alert"
          title={gettext("Não deu para abrir a lixeira")}
          hint={gettext("Pode ter sido um instante de rede ou da caixa. Tente de novo.")}
        >
          <.button variant="secondary" phx-click="retry-load">
            {gettext("Tentar de novo")}
          </.button>
        </.empty_state>

        <.empty_state
          :if={@items == [] and @folders == [] and not @load_error}
          icon="trash"
          title={gettext("Lixeira vazia")}
          hint={gettext("Nada esperando para ser apagado.")}
        />
      </div>
    </Layouts.app>
    """
  end
end
