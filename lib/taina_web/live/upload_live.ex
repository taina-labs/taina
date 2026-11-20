defmodule TainaWeb.UploadLive do
  @moduledoc """
  Envio de arquivos (boards "Servico / Ybira Enviar / enviando"
  cc1037dc-e8ab-80cc-8008-d5e2162dfb73 e "erro cota" ...d5e218361ef0): tela
  empurrada do Documentos. O voltar aponta a pasta de destino ("< Atas").

  `UploadManagerLive` owns the inputs and transfer state. This LiveView resolves
  the current folder, supplies route context, and renders the upload screen
  header. `?pasta=<rkey>` defines the destination.
  """

  use TainaWeb, :live_view

  alias Taina.Ybira
  alias TainaWeb.InternalPath
  alias TainaWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, gettext("Documentos"))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    scope = socket.assigns.current_scope
    {folder, folder_note} = resolve_folder(scope, params["pasta"])
    return_to = InternalPath.return_to(params["return_to"], back_path(folder))

    route_context = %{
      folder_rkey: folder && folder.rkey,
      return_to: return_to
    }

    socket =
      socket
      |> assign(:folder, folder)
      |> assign(:upload_route_context, route_context)
      |> maybe_flash_folder_note(folder_note)
      |> notify_upload_manager(route_context)

    {:noreply, socket}
  end

  # Onde os arquivos caíram: na pasta alvo, ou no início já na casa (o
  # destino de quem chega pela raiz).
  defp back_path(nil), do: ~p"/documentos"
  defp back_path(folder), do: ~p"/documentos/pasta/#{folder.rkey}"

  # Pasta inexistente ou casa de outra pessoa: sobe para a raiz sem travar o
  # envio; o flash explica por que a pasta sumiu do voltar.
  defp resolve_folder(_scope, nil), do: {nil, nil}

  defp resolve_folder(scope, rkey) do
    case Ybira.get_folder(scope, rkey) do
      {:ok, folder} ->
        {folder, nil}

      {:error, _reason} ->
        {nil, gettext("A pasta original não está mais disponível. O envio vai para o início.")}
    end
  end

  defp maybe_flash_folder_note(socket, nil), do: socket
  defp maybe_flash_folder_note(socket, note), do: put_flash(socket, :error, note)

  defp notify_upload_manager(socket, route_context) do
    if connected?(socket) do
      Phoenix.PubSub.broadcast(
        Taina.PubSub,
        Layouts.upload_manager_topic(socket.assigns.upload_manager_id),
        {:upload_manager_route_context, route_context}
      )
    end

    socket
  end

  defp folder_back_label(nil), do: nil
  defp folder_back_label(folder), do: back_label(folder.nome)

  defp return_label(return_to, folder) do
    return_to
    |> URI.parse()
    |> Map.fetch!(:path)
    |> return_label_from_path(folder)
    |> back_label()
  end

  defp return_label_from_path(path, _folder) when path in ["/galeria", "/galeria/linha-do-tempo"], do: gettext("Galeria")

  defp return_label_from_path("/documentos/praca", _folder), do: gettext("Praça")
  defp return_label_from_path("/documentos/lixeira", _folder), do: gettext("Lixeira")

  defp return_label_from_path("/documentos/pasta/" <> _folder_id, folder),
    do: folder_back_label(folder) || gettext("Documentos")

  defp return_label_from_path("/moradores", _folder), do: gettext("Moradores")
  defp return_label_from_path("/conta", _folder), do: gettext("Conta")
  defp return_label_from_path(_path, folder), do: folder_back_label(folder) || gettext("Casa")

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <.flash_group flash={@flash} />
    <a class="skip-link" href="#upload-manager-main-content">{gettext("Pular para o conteúdo")}</a>
    <.page_header
      title={gettext("Documentos")}
      back={@upload_route_context.return_to}
      back_label={return_label(@upload_route_context.return_to, @folder)}
    />
    """
  end
end
