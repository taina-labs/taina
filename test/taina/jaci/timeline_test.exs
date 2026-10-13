defmodule Taina.Jaci.TimelineTest do
  use ExUnit.Case, async: true

  alias Taina.Jaci.Timeline

  # A data efetiva vem resolvida da consulta (`COALESCE(taken_at, inserted_at)`);
  # no SQLite ela pode chegar como %NaiveDateTime{} (fallback do upload) ou
  # como texto ISO8601 (o `taken_at` do JSON do EXIF).
  defp photo(ts), do: %{file: %Ypy.Ybira.File{id: 1}, ts: ts}

  describe "group_by_date/1" do
    test "buckets consecutive same-day photos, keeping order" do
      rows = [
        photo(~N[2023-07-16 10:00:00]),
        photo("2023-07-15T18:00:00"),
        photo(~N[2023-07-15 09:00:00])
      ]

      assert [
               %{date: ~D[2023-07-16], photos: [_]},
               %{date: ~D[2023-07-15], photos: [_, _]}
             ] = Timeline.group_by_date(rows)
    end

    test "empty input yields no groups" do
      assert Timeline.group_by_date([]) == []
    end
  end
end
