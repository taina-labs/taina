defmodule TainaWeb.API.DeviceController do
  @moduledoc "Os dispositivos de quem esta agindo (RFC_005 secao 9): listar e revogar."

  use TainaWeb, :controller

  alias Taina.Maraca
  alias TainaWeb.API.Error
  alias TainaWeb.API.Serializer
  alias Ypy.Wire

  def index(conn, _params) do
    case Maraca.list_devices(conn.assigns[:current_scope]) do
      {:ok, devices} ->
        current_public_id =
          case conn.assigns[:api_device] do
            %{public_id: public_id} -> public_id
            _ -> nil
          end

        items = Enum.map(devices, &Serializer.device(&1, current_public_id))
        json(conn, Wire.page(items, nil))

      {:error, reason} ->
        Error.reply(conn, reason)
    end
  end

  def delete(conn, %{"id" => device_public_id}) do
    case Maraca.revoke_device(conn.assigns[:current_scope], device_public_id) do
      {:ok, _device} -> send_resp(conn, 204, "")
      {:error, reason} -> Error.reply(conn, reason)
    end
  end
end
