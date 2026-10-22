defmodule Taina.Jaci.TimelineTest do
  use ExUnit.Case, async: true

  alias Taina.Jaci.Timeline

  # A data efetiva vem resolvida da consulta (`COALESCE` normalizado a epoch
  # de segundos, UTC): o `taken_at` do EXIF e o fallback do upload chegam na
  # mesma representacao inteira.
  defp photo(epoch), do: %{file: %Ypy.Ybira.File{id: 1}, ts: epoch}

  describe "group_by_date/1" do
    test "buckets consecutive same-day photos, keeping order" do
      rows = [
        ~D[2023-07-16] |> DateTime.new!(~T[10:00:00]) |> DateTime.to_unix() |> photo(),
        ~D[2023-07-15] |> DateTime.new!(~T[18:00:00]) |> DateTime.to_unix() |> photo(),
        ~D[2023-07-15] |> DateTime.new!(~T[09:00:00]) |> DateTime.to_unix() |> photo()
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
