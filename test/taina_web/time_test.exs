defmodule TainaWeb.TimeTest do
  use ExUnit.Case, async: true

  alias TainaWeb.Time

  test "local hour follows the community offset at greeting boundaries" do
    assert local_hour("2026-01-01T07:59:59Z") == 4
    assert local_hour("2026-01-01T08:00:00Z") == 5
    assert local_hour("2026-01-01T15:00:00Z") == 12
    assert local_hour("2026-01-01T21:00:00Z") == 18
  end

  defp local_hour(iso8601) do
    {:ok, at, 0} = DateTime.from_iso8601(iso8601)
    Time.local_hour(at)
  end
end
