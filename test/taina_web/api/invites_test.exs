defmodule TainaWeb.API.InvitesTest do
  use TainaWeb.ConnCase, async: true

  import Taina.Fixtures

  alias Taina.Maraca
  alias Taina.Scope

  @moduletag capture_log: true

  describe "convite pelo app" do
    setup %{conn: conn} do
      tekoa = tekoa_fixture()
      zelador = zelador_fixture(tekoa)
      {:ok, %{ava: invited, token: token}} = Maraca.invite_user(zelador, tekoa)
      %{conn: conn, tekoa: tekoa, zelador: zelador, invited: invited, token: token}
    end

    test "status do convite pendente: valida e nao exige auth", %{conn: conn, token: token} do
      body = conn |> get(~p"/api/v1/invites/#{token}") |> json_response(200)
      assert body == %{"valid" => true}
    end

    test "status de token invalido responde 401 no envelope", %{conn: conn} do
      body = conn |> get(~p"/api/v1/invites/token-falso") |> json_response(401)
      assert body["error"]["code"] == "invalid_token"
    end

    test "aceite devolve a sessao com o token de dispositivo, sem auth", %{
      conn: conn,
      tekoa: tekoa,
      invited: invited,
      token: token
    } do
      body =
        conn
        |> post(~p"/api/v1/invites/#{token}/accept", %{
          "username" => "maria",
          "password" => "senhasegura123",
          "display_name" => "Maria",
          "device_name" => "Celular da Maria"
        })
        |> json_response(201)

      assert String.starts_with?(body["token"], "tnd_")
      assert body["me"]["public_id"] == invited.public_id
      assert body["tekoa"]["public_id"] == tekoa.public_id
      assert body["device"]["name"] == "Celular da Maria"
    end

    test "convite usado nao volta a servir", %{conn: conn, token: token} do
      assert conn
             |> post(~p"/api/v1/invites/#{token}/accept", %{
               "username" => "maria",
               "password" => "senhasegura123"
             })
             |> json_response(201)

      body =
        conn
        |> post(~p"/api/v1/invites/#{token}/accept", %{
          "username" => "outra",
          "password" => "senhasegura123"
        })
        |> json_response(401)

      assert body["error"]["code"] == "invalid_token"
    end

    test "aceite com token invalido responde 401", %{conn: conn} do
      body =
        conn
        |> post(~p"/api/v1/invites/token-falso/accept", %{
          "username" => "maria",
          "password" => "senhasegura123"
        })
        |> json_response(401)

      assert body["error"]["code"] == "invalid_token"
    end

    test "aceite com username tomado responde 422 com details", %{
      conn: conn,
      tekoa: tekoa,
      token: token
    } do
      _tomado = active_ava_fixture(tekoa, %{username: "tomado"})

      body =
        conn
        |> post(~p"/api/v1/invites/#{token}/accept", %{
          "username" => "tomado",
          "password" => "senhasegura123"
        })
        |> json_response(422)

      assert body["error"]["code"] == "validation_failed"
      assert body["error"]["details"]["username"]
    end
  end

  describe "redefinicao de senha pelo app" do
    setup %{conn: conn} do
      tekoa = tekoa_fixture()
      zelador = zelador_fixture(tekoa)
      morador = active_ava_fixture(tekoa)
      {:ok, %{token: token}} = Maraca.mint_reset_link(Scope.new(zelador, tekoa), morador)

      %{conn: conn, tekoa: tekoa, morador: morador, token: token}
    end

    test "status do link pendente: valida e nao exige auth", %{conn: conn, token: token} do
      body = conn |> get(~p"/api/v1/password-resets/#{token}") |> json_response(200)
      assert body == %{"valid" => true}
    end

    test "status de token invalido responde 401 no envelope", %{conn: conn} do
      body = conn |> get(~p"/api/v1/password-resets/token-falso") |> json_response(401)
      assert body["error"]["code"] == "invalid_token"
    end

    test "redefinicao devolve a sessao e a senha nova entra, a velha nao", %{
      conn: conn,
      morador: morador,
      token: token
    } do
      body =
        conn
        |> post(~p"/api/v1/password-resets/#{token}", %{
          "password" => "novasenha123",
          "device_name" => "Celular novo"
        })
        |> json_response(201)

      assert String.starts_with?(body["token"], "tnd_")
      assert body["me"]["public_id"] == morador.public_id
      assert body["device"]["name"] == "Celular novo"

      assert conn
             |> post(~p"/api/v1/session", %{
               "username" => morador.username,
               "password" => "novasenha123"
             })
             |> json_response(201)

      body =
        conn
        |> post(~p"/api/v1/session", %{
          "username" => morador.username,
          "password" => "senhasegura123"
        })
        |> json_response(401)

      assert body["error"]["code"] == "invalid_credentials"
    end

    test "redefinicao com token invalido responde 401", %{conn: conn} do
      body =
        conn
        |> post(~p"/api/v1/password-resets/token-falso", %{"password" => "novasenha123"})
        |> json_response(401)

      assert body["error"]["code"] == "invalid_token"
    end

    test "senha curta responde 422 com details", %{conn: conn, token: token} do
      body =
        conn
        |> post(~p"/api/v1/password-resets/#{token}", %{"password" => "curta"})
        |> json_response(422)

      assert body["error"]["code"] == "validation_failed"
      assert body["error"]["details"]["password"]
    end
  end
end
