defmodule Taina.RlsIsolationTest do
  @moduledoc """
  Prova que o isolamento RLS funciona de verdade no banco.

  O usuário de teste padrão (`postgres`) é superuser e **ignora RLS por
  definição** — por isso este teste cria uma role restrita (`taina_rls_probe`)
  e conecta via Postgrex puro, fora do sandbox do Ecto. Os dados são
  comitados de verdade e limpos ao final; o módulo precisa ser `async: false`
  porque o índice `single_tekoa_enforcement` permite apenas uma Tekoa viva.

  Com modo single-tekoa não há segunda Tekoa para testar vazamento cruzado;
  o que se valida aqui é o mecanismo: sem contexto → zero linhas; contexto
  correto → linhas da Tekoa; contexto errado → zero linhas.
  """

  use ExUnit.Case, async: false

  @probe_role "taina_rls_probe"
  @probe_email "rls@probe.test"

  setup_all do
    admin_opts = conn_opts()
    {:ok, admin} = Postgrex.start_link(admin_opts)

    Postgrex.query!(
      admin,
      """
      DO $$ BEGIN
        CREATE ROLE #{@probe_role} LOGIN PASSWORD '#{@probe_role}';
      EXCEPTION WHEN duplicate_object THEN NULL;
      END $$
      """,
      []
    )

    Postgrex.query!(admin, "GRANT USAGE ON SCHEMA maraca, ybira, guara TO #{@probe_role}", [])

    Postgrex.query!(
      admin,
      "GRANT SELECT ON ALL TABLES IN SCHEMA maraca, ybira, guara TO #{@probe_role}",
      []
    )

    tekoa_public_id = Nanoid.generate(12)

    %{rows: [[tekoa_id]]} =
      Postgrex.query!(
        admin,
        """
        INSERT INTO maraca.tekoas (name, public_id, storage_used_bytes, inserted_at, updated_at)
        VALUES ('RLS Probe', $1, 0, now(), now())
        RETURNING id
        """,
        [tekoa_public_id]
      )

    Postgrex.query!(
      admin,
      """
      INSERT INTO maraca.avas (tekoa_id, username, email, inserted_at, updated_at)
      VALUES ($1, 'rlsprobe', $2, now(), now())
      """,
      [tekoa_id, @probe_email]
    )

    probe_opts =
      Keyword.merge(admin_opts,
        username: @probe_role,
        password: @probe_role,
        pool_size: 1
      )

    {:ok, probe} = Postgrex.start_link(probe_opts)

    on_exit(fn ->
      {:ok, cleaner} = Postgrex.start_link(admin_opts)
      Postgrex.query!(cleaner, "DELETE FROM maraca.avas WHERE email = $1", [@probe_email])
      Postgrex.query!(cleaner, "DELETE FROM maraca.tekoas WHERE public_id = $1", [tekoa_public_id])
      GenServer.stop(cleaner)
    end)

    %{admin: admin, probe: probe, tekoa_public_id: tekoa_public_id}
  end

  test "restricted role sees nothing without tekoa context", %{probe: probe} do
    assert %{rows: [[0]]} = Postgrex.query!(probe, "SELECT count(*) FROM maraca.tekoas", [])
    assert %{rows: [[0]]} = Postgrex.query!(probe, "SELECT count(*) FROM maraca.avas", [])
  end

  test "restricted role sees only the current tekoa with context set", %{
    probe: probe,
    tekoa_public_id: tekoa_public_id
  } do
    {:ok, rows} =
      Postgrex.transaction(probe, fn conn ->
        Postgrex.query!(conn, "SELECT set_config('app.current_tekoa_id', $1, true)", [
          tekoa_public_id
        ])

        %{rows: rows} = Postgrex.query!(conn, "SELECT public_id FROM maraca.tekoas", [])
        rows
      end)

    assert rows == [[tekoa_public_id]]
  end

  test "restricted role sees nothing with a wrong tekoa context", %{probe: probe} do
    {:ok, count} =
      Postgrex.transaction(probe, fn conn ->
        Postgrex.query!(conn, "SELECT set_config('app.current_tekoa_id', 'tekoa_errada', true)", [])

        %{rows: [[count]]} = Postgrex.query!(conn, "SELECT count(*) FROM maraca.avas", [])
        count
      end)

    assert count == 0
  end

  test "superuser bypasses RLS — production must not connect as superuser", %{
    admin: admin,
    tekoa_public_id: tekoa_public_id
  } do
    %{rows: rows} =
      Postgrex.query!(admin, "SELECT public_id FROM maraca.tekoas WHERE public_id = $1", [
        tekoa_public_id
      ])

    assert rows == [[tekoa_public_id]]
  end

  defp conn_opts do
    config = Taina.Repo.config()

    if url = config[:url] do
      uri = URI.parse(url)
      [username, password] = String.split(uri.userinfo, ":")

      [
        hostname: uri.host,
        port: uri.port || 5432,
        username: username,
        password: password,
        database: String.trim_leading(uri.path, "/"),
        pool_size: 1
      ]
    else
      config
      |> Keyword.take([:hostname, :port, :username, :password, :database])
      |> Keyword.put_new(:port, 5432)
      |> Keyword.put(:pool_size, 1)
    end
  end
end
