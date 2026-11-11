defmodule TainaWeb.ConnCase do
  @moduledoc """
  Isolates database writes with the SQL sandbox and imports helpers for connection and LiveView tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use TainaWeb, :verified_routes

      import Phoenix.ConnTest
      import Plug.Conn
      import TainaWeb.ConnCase
      # The default endpoint for testing
      # Phoenix.ConnTest reads this exact caller attribute name.
      # credo:disable-for-next-line OptimumCredo.Check.Warning.CallerModuleAttributes
      @endpoint TainaWeb.Endpoint

      # Import conveniences for testing with connections
    end
  end

  setup tags do
    Taina.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Loga um Ava na sessão de teste (cookie), do jeito que a pipeline
  `:authenticated` espera, `Maraca.get_session_user/1` lê `:ava_id`.
  """
  def log_in(conn, ava) do
    Plug.Test.init_test_session(conn, %{ava_id: ava.public_id})
  end

  @doc """
  Autentica a conn com um token de dispositivo da pessoa, como o app faz:
  cria o token e poe o `Authorization: Bearer`.
  """
  # Test-only setup creates a token through the database so requests can exercise
  # the normal authentication pipeline.
  # credo:disable-for-next-line OeditusCredo.Check.Warning.BlockingInPlug
  def authorize_device(conn, ava) do
    tekoa = Taina.Repo.get!(Ypy.Maraca.Tekoa, ava.tekoa_id, skip_tekoa_id: true)
    {:ok, %{token: token}} = Taina.Maraca.create_device_token(Taina.Scope.new(ava, tekoa), "teste")

    Plug.Conn.put_req_header(conn, "authorization", "Bearer " <> token)
  end
end
