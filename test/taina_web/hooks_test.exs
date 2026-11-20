defmodule TainaWeb.HooksTest do
  use Taina.DataCase, async: true

  import Taina.Fixtures

  alias Phoenix.LiveView.Socket
  alias Taina.Scope
  alias TainaWeb.Hooks
  alias TainaWeb.Layouts

  test "root mounts notify the same manager about route visibility" do
    tekoa = tekoa_fixture()
    scope = tekoa |> active_ava_fixture() |> Scope.new(tekoa)
    manager_id = Ecto.UUID.generate()
    topic = Layouts.upload_manager_topic(manager_id)
    session = %{"upload_manager_id" => manager_id}
    :ok = Phoenix.PubSub.subscribe(Taina.PubSub, topic)

    assert {:cont, _home_socket} = Hooks.on_mount(:shell, %{}, session, socket(TainaWeb.HomeLive, scope))
    assert_receive {:upload_manager_visibility, false}

    assert {:cont, _upload_socket} =
             Hooks.on_mount(:shell, %{}, session, socket(TainaWeb.UploadLive, scope))

    assert_receive {:upload_manager_visibility, true}
  end

  defp socket(view, scope) do
    %Socket{
      endpoint: TainaWeb.Endpoint,
      router: TainaWeb.Router,
      view: view,
      transport_pid: self(),
      assigns: %{__changed__: %{}, current_scope: scope},
      private: %{
        lifecycle: %{
          mount: [],
          handle_params: [],
          handle_event: [],
          handle_async: [],
          handle_info: [],
          after_render: []
        }
      }
    }
  end
end
