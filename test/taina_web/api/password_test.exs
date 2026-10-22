defmodule TainaWeb.API.PasswordTest do
  use TainaWeb.ConnCase, async: true

  import Taina.Fixtures

  @moduletag capture_log: true

  setup do
    tekoa = tekoa_fixture()
    ava = active_ava_fixture(tekoa)

    # Um segundo aparelho logado, para o teste de revogacao: o token cru so
    # volta na resposta do login.
    %{"token" => other_token} =
      build_conn()
      |> post(~p"/api/v1/session", %{"username" => ava.username, "password" => "senhasegura123"})
      |> json_response(201)

    %{
      ava: ava,
      conn: authorize_device(build_conn(), ava),
      other_token: other_token
    }
  end

  test "sem Bearer responde 401" do
    body =
      build_conn()
      |> post(~p"/api/v1/session/password", %{"current_password" => "x", "new_password" => "y"})
      |> json_response(401)

    assert body["error"]["code"] == "not_authenticated"
  end

  test "a troca revoga os OUTROS aparelhos e mantem o da chamada", %{conn: conn, other_token: other_token} do
    assert %{"ok" => true} =
             conn
             |> post(~p"/api/v1/session/password", %{
               "current_password" => "senhasegura123",
               "new_password" => "frase-longa-nova"
             })
             |> json_response(200)

    # A chamada continua valendo...
    assert conn |> get(~p"/api/v1/me") |> response(200)

    # ...e o outro aparelho, nao.
    assert build_conn()
           |> put_req_header("authorization", "Bearer " <> other_token)
           |> get(~p"/api/v1/me")
           |> json_response(401)
  end

  test "senha atual errada responde 403 invalid_credentials", %{conn: conn} do
    body =
      conn
      |> post(~p"/api/v1/session/password", %{
        "current_password" => "errada",
        "new_password" => "frase-longa-nova"
      })
      |> json_response(403)

    assert body["error"]["code"] == "invalid_credentials"
  end

  test "nova senha fraca responde 422 validation_failed", %{conn: conn} do
    body =
      conn
      |> post(~p"/api/v1/session/password", %{
        "current_password" => "senhasegura123",
        "new_password" => "curta"
      })
      |> json_response(422)

    assert body["error"]["code"] == "validation_failed"
  end
end
