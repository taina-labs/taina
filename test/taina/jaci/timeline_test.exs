defmodule Taina.Jaci.TimelineTest do
  use ExUnit.Case, async: true

  alias Taina.Jaci.Timeline
  alias Taina.Ybira.File, as: YbiraFile

  defp photo(metadata, inserted_at), do: %YbiraFile{metadata: metadata, inserted_at: inserted_at}

  describe "effective_datetime/1" do
    test "prefers the EXIF capture time when present" do
      p = photo(%{"taken_at" => "2023-07-15T09:00:00"}, ~N[2026-01-01 00:00:00])
      assert Timeline.effective_datetime(p) == ~N[2023-07-15 09:00:00]
    end

    test "falls back to upload time without (or with invalid) EXIF" do
      assert Timeline.effective_datetime(photo(%{}, ~N[2026-01-01 12:00:00])) ==
               ~N[2026-01-01 12:00:00]

      assert Timeline.effective_datetime(photo(%{"taken_at" => "lixo"}, ~N[2026-01-01 12:00:00])) ==
               ~N[2026-01-01 12:00:00]
    end
  end

  describe "group_by_date/1" do
    test "buckets consecutive same-day photos, keeping order" do
      photos = [
        photo(%{"taken_at" => "2023-07-16T10:00:00"}, ~N[2026-01-01 00:00:00]),
        photo(%{"taken_at" => "2023-07-15T18:00:00"}, ~N[2026-01-01 00:00:00]),
        photo(%{"taken_at" => "2023-07-15T09:00:00"}, ~N[2026-01-01 00:00:00])
      ]

      assert [
               %{date: ~D[2023-07-16], photos: [_]},
               %{date: ~D[2023-07-15], photos: [_, _]}
             ] = Timeline.group_by_date(photos)
    end

    test "empty input yields no groups" do
      assert Timeline.group_by_date([]) == []
    end
  end
end
