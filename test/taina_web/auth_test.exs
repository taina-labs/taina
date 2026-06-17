defmodule TainaWeb.AuthTest do
  use TainaWeb.ConnCase, async: true

  import Taina.Fixtures

  alias Taina.Scope
  alias TainaWeb.Auth

  setup %{conn: conn} do
    scope = scope_fixture()
    %{conn: conn, ava: scope.ava, tekoa: scope.tekoa}
  end

  # Socket cru com o mínimo que `assign_new`/`put_flash` esperam.
  defp socket do
    %Phoenix.LiveView.Socket{
      endpoint: TainaWeb.Endpoint,
      assigns: %{__changed__: %{}, flash: %{}}
    }
  end

  describe "fetch_current_scope/2 (plug)" do
    test "assigns the Scope for a logged-in conn", %{conn: conn, ava: ava, tekoa: tekoa} do
      conn = conn |> log_in(ava) |> Auth.fetch_current_scope([])

      assert %Scope{} = scope = conn.assigns.current_scope
      assert scope.ava.id == ava.id
      assert scope.tekoa.id == tekoa.id
    end

    test "assigns nil without a session", %{conn: conn} do
      conn = conn |> Plug.Test.init_test_session(%{}) |> Auth.fetch_current_scope([])

      assert conn.assigns.current_scope == nil
    end
  end

  describe "require_authenticated/2 (plug)" do
    test "lets a logged-in conn through", %{conn: conn, ava: ava} do
      conn =
        conn
        |> log_in(ava)
        |> Auth.fetch_current_scope([])
        |> Auth.require_authenticated([])

      refute conn.halted
    end

    test "redirects an anonymous conn to the login page", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> Phoenix.Controller.fetch_flash([])
        |> Auth.fetch_current_scope([])
        |> Auth.require_authenticated([])

      assert conn.halted
      assert redirected_to(conn) == "/login"
    end
  end

  describe "on_mount/4" do
    test "mount_current_scope assigns the scope from the session", %{ava: ava, tekoa: tekoa} do
      {:cont, socket} =
        Auth.on_mount(:mount_current_scope, %{}, %{"ava_id" => ava.public_id}, socket())

      assert %Scope{} = scope = socket.assigns.current_scope
      assert scope.ava.id == ava.id
      assert scope.tekoa.id == tekoa.id
    end

    test "mount_current_scope assigns nil without a session" do
      {:cont, socket} = Auth.on_mount(:mount_current_scope, %{}, %{}, socket())

      assert socket.assigns.current_scope == nil
    end

    test "require_authenticated continues for a logged-in session", %{ava: ava} do
      assert {:cont, socket} =
               Auth.on_mount(:require_authenticated, %{}, %{"ava_id" => ava.public_id}, socket())

      assert %Scope{} = socket.assigns.current_scope
    end

    test "require_authenticated halts and redirects without a session" do
      assert {:halt, socket} = Auth.on_mount(:require_authenticated, %{}, %{}, socket())
      assert socket.redirected == {:redirect, %{to: "/login", status: 302}}
    end
  end
end
