defmodule TainaWeb.Hooks do
  @moduledoc """
  `on_mount` compartilhado. `:shell` (telas autenticadas, com `current_scope`
  já atribuído pelo Auth) inscreve-se nos tópicos de Maracá e Ybira Uploads
  quando conectado. Maracá mantém os eventos por tela; os resultados terminais
  de upload são conferidos no estado persistido e agregados em um flash, exceto
  em Enviar, onde o manager atualiza a lista.

  `:connection` (cascas de auth, spec 6.5): atribui `secure_connection?` a partir
  do URI da requisição; a decisão vive na função pura `secure_connection?/1`,
  o hook só atribui.
  """

  use TainaWeb, :verified_routes
  use Gettext, backend: TainaWeb.Gettext

  import Phoenix.LiveView, only: [connected?: 1, get_connect_info: 2]

  alias Taina.Maraca
  alias Taina.Ybira.Uploads
  alias TainaWeb.Layouts

  @upload_notification_window_ms 600
  @upload_notification_dedup_limit 512

  def on_mount(:shell, _params, session, socket) do
    scope = socket.assigns.current_scope

    socket =
      socket
      |> Phoenix.Component.assign_new(:upload_notification_state, &empty_upload_notification_state/0)
      |> Phoenix.LiveView.attach_hook(
        :upload_notifications,
        :handle_info,
        &handle_upload_notification/2
      )

    if connected?(socket) and scope do
      Maraca.subscribe_to_my_events(scope.ava)
      Uploads.subscribe(scope)
      broadcast_manager_visibility(socket, session)
    end

    {:cont, socket}
  end

  def on_mount(:connection, _params, _session, socket) do
    uri = if connected?(socket), do: get_connect_info(socket, :uri), else: Map.get(socket, :host_uri)
    {:cont, Phoenix.Component.assign(socket, :secure_connection?, secure_connection?(uri))}
  end

  defp broadcast_manager_visibility(%{view: view}, %{"upload_manager_id" => <<_first::utf8, _rest::binary>> = manager_id}) do
    Phoenix.PubSub.broadcast(
      Taina.PubSub,
      Layouts.upload_manager_topic(manager_id),
      {:upload_manager_visibility, view == TainaWeb.UploadLive}
    )
  end

  defp broadcast_manager_visibility(_socket, _session), do: :ok

  defp empty_upload_notification_state do
    %{seen: MapSet.new(), seen_order: [], pending: [], timer_token: nil}
  end

  defp handle_upload_notification({:ybira_upload, _public_id, state}, socket) when state not in [:completed, :failed],
    do: {:halt, socket}

  defp handle_upload_notification({:ybira_upload, _public_id, state}, %{view: TainaWeb.UploadLive} = socket)
       when state in [:completed, :failed], do: {:halt, socket}

  defp handle_upload_notification({:ybira_upload, public_id, state}, socket)
       when state in [:completed, :failed] and is_binary(public_id) do
    case persistent_terminal_upload(socket.assigns.current_scope, public_id) do
      nil ->
        {:halt, socket}

      upload ->
        queue_upload_notification(socket, upload)
    end
  end

  defp handle_upload_notification({:flush_upload_notifications, token}, socket) do
    flush_upload_notifications(socket, token)
  end

  defp handle_upload_notification(_message, socket), do: {:cont, socket}

  defp persistent_terminal_upload(scope, public_id) do
    case Uploads.list(scope, limit: 100) do
      {:ok, uploads} ->
        Enum.find(uploads, fn upload ->
          upload.public_id == public_id and upload.state in [:completed, :failed]
        end)

      {:error, _reason} ->
        nil
    end
  end

  defp queue_upload_notification(socket, upload) do
    state = socket.assigns.upload_notification_state
    key = {upload.public_id, upload.state}

    if MapSet.member?(state.seen, key) do
      {:halt, socket}
    else
      state = remember_terminal_upload(state, key)
      pending = [%{filename: upload.filename, state: upload.state} | state.pending]

      {state, socket} =
        if state.timer_token do
          {%{state | pending: pending}, socket}
        else
          token = make_ref()
          Process.send_after(self(), {:flush_upload_notifications, token}, @upload_notification_window_ms)
          {%{state | pending: pending, timer_token: token}, socket}
        end

      {:halt, Phoenix.Component.assign(socket, :upload_notification_state, state)}
    end
  end

  defp remember_terminal_upload(state, key) do
    seen_order = Enum.take([key | state.seen_order], @upload_notification_dedup_limit)
    %{state | seen: MapSet.new(seen_order), seen_order: seen_order}
  end

  defp flush_upload_notifications(socket, token) do
    state = socket.assigns.upload_notification_state

    if state.timer_token == token do
      notifications = Enum.reverse(state.pending)
      state = %{state | pending: [], timer_token: nil}
      socket = Phoenix.Component.assign(socket, :upload_notification_state, state)

      case upload_flash(notifications) do
        nil ->
          {:halt, socket}

        {kind, message} ->
          {:halt, Phoenix.LiveView.put_flash(socket, kind, message)}
      end
    else
      {:halt, socket}
    end
  end

  defp upload_flash([]), do: nil

  defp upload_flash([%{state: :completed, filename: filename}]) do
    {:info, gettext("%{filename} foi enviado.", filename: filename)}
  end

  defp upload_flash([%{state: :failed, filename: filename}]) do
    {:error, gettext("Não foi possível enviar %{filename}. Confira os envios recentes.", filename: filename)}
  end

  defp upload_flash(notifications) do
    {completed, failed} = Enum.split_with(notifications, &(&1.state == :completed))

    cond do
      failed == [] ->
        count = length(completed)
        {:info, ngettext("%{count} arquivo enviado", "%{count} arquivos enviados", count, count: count)}

      completed == [] ->
        count = length(failed)

        {:error,
         gettext("%{failures}. Confira os envios recentes.",
           failures:
             ngettext(
               "%{count} envio falhou",
               "%{count} envios falharam",
               count,
               count: count
             )
         )}

      true ->
        success_count = length(completed)
        failure_count = length(failed)

        success_text =
          ngettext(
            "%{count} arquivo enviado",
            "%{count} arquivos enviados",
            success_count,
            count: success_count
          )

        failure_text =
          ngettext(
            "%{count} envio falhou",
            "%{count} envios falharam",
            failure_count,
            count: failure_count
          )

        {:error,
         gettext("%{successes}; %{failures}. Confira os envios recentes.",
           successes: success_text,
           failures: failure_text
         )}
    end
  end

  @doc """
  Decisão pura de conexão segura (spec 6.5): https é seguro sempre; http em
  host de loopback (localhost, 127.0.0.1, ::1) é a própria máquina, seguro;
  http em qualquer outro host, inseguro. Sem URI, assume segura.
  """
  def secure_connection?(nil), do: true

  def secure_connection?(%URI{scheme: scheme, host: host}) do
    case {scheme, host} do
      {"https", _host} -> true
      {"http", "localhost"} -> true
      {"http", "127.0.0.1"} -> true
      {"http", "::1"} -> true
      {"http", _host} -> false
      _scheme -> true
    end
  end

  def secure_connection?(uri) when is_binary(uri), do: secure_connection?(URI.parse(uri))
end
