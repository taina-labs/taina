defmodule Taina.YbiraUploadLimitTest do
  use Taina.DataCase, async: false

  import Taina.Fixtures

  alias Taina.Scope
  alias Taina.Ybira

  test "rejects a blob above the configured limit before storing it" do
    previous = Application.get_env(:taina, :upload, [])
    Application.put_env(:taina, :upload, Keyword.put(previous, :max_blob_size, 4))

    on_exit(fn -> Application.put_env(:taina, :upload, previous) end)

    tekoa = tekoa_fixture()
    ava = active_ava_fixture(tekoa)
    scope = Scope.new(ava, tekoa)
    path = tmp_upload_fixture("cinco")

    assert {:error, :blob_too_large} = Ybira.upload(scope, path)
    assert {:ok, %{items: []}} = Ybira.list_files(scope)
  end
end
