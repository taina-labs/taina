defmodule TainaWeb.API.DeviceController do
  @moduledoc "Os dispositivos de quem esta agindo (RFC_005 secao 9): listar e revogar."

  use TainaWeb, :controller

  alias Taina.Maraca
  alias TainaWeb.API.Error
  alias TainaWeb.API.Serializer
  alias Ypy.Wire

  def index(conn, _params) do
    case Maraca.list_devices(conn.assigns[:current_scope]) do
      {:ok, devices} -> json(conn, Wire.page(Enum.map(devices, &Serializer.device/1), nil))
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  def delete(conn, %{"id" => device_public_id}) do
    case Maraca.revoke_device(conn.assigns[:current_scope], device_public_id) do
      {:ok, _device} -> send_resp(conn, 204, "")
      {:error, reason} -> Error.reply(conn, reason)
    end
  end
end
