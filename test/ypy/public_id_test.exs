defmodule Ypy.PublicIdTest do
  use ExUnit.Case, async: true

  alias Ypy.PublicId

  @alphabet ~c"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"

  test "generates 12 characters from the URL-safe alphabet" do
    for _ <- 1..200 do
      id = PublicId.generate()
      assert byte_size(id) == 12
      assert id |> String.to_charlist() |> Enum.all?(&(&1 in @alphabet))
      assert PublicId.valid?(id)
    end
  end

  test "generates distinct ids" do
    ids = for _ <- 1..500, do: PublicId.generate()
    assert Enum.uniq(ids) == ids
  end

  test "valid? accepts the exact shape" do
    assert PublicId.valid?("V1StGXR8_Z5j")
    assert PublicId.valid?(String.duplicate("-", 12))
  end

  test "valid? rejects everything else" do
    for id <- ["", "V1StGXR8_Z5", "V1StGXR8_Z5jj", "V1StGXR8 Z5j", "V1StGXR8+Z5j", "mau id"] do
      refute PublicId.valid?(id), "expected #{inspect(id)} to be invalid"
    end
  end

  test "cast validates the shape" do
    assert PublicId.cast("V1StGXR8_Z5j") == {:ok, "V1StGXR8_Z5j"}
    assert PublicId.cast("V1StGXR8_Z5jj") == :error
    assert PublicId.cast(12_345) == :error
    assert PublicId.cast(nil) == :error
  end

  test "load and dump pass binaries through" do
    assert PublicId.load("V1StGXR8_Z5j") == {:ok, "V1StGXR8_Z5j"}
    assert PublicId.dump("V1StGXR8_Z5j") == {:ok, "V1StGXR8_Z5j"}
    assert PublicId.dump(12_345) == :error
  end

  test "autogenerate is a valid id" do
    id = PublicId.autogenerate()
    assert PublicId.valid?(id)
  end

  test "the type is :string" do
    assert PublicId.type() == :string
  end
end
