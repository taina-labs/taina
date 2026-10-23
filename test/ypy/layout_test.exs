defmodule Ypy.LayoutTest do
  use ExUnit.Case, async: true

  alias Ypy.Layout

  test "maps a data dir to the db file, blobs/ and keys/" do
    layout = Layout.from_dir("/var/lib/taina")

    assert layout.dir == "/var/lib/taina"
    assert layout.db == "/var/lib/taina/db.sqlite"
    assert layout.blobs == "/var/lib/taina/blobs"
    assert layout.keys == "/var/lib/taina/keys"
  end

  test "tolerates a trailing slash" do
    layout = Layout.from_dir("/var/lib/taina/")

    assert layout.db == "/var/lib/taina/db.sqlite"
    assert layout.blobs == "/var/lib/taina/blobs"
    assert layout.keys == "/var/lib/taina/keys"
  end

  test "the three paths live under dir" do
    layout = Layout.from_dir("/dados")

    for path <- [layout.db, layout.blobs, layout.keys] do
      assert String.starts_with?(path, "/dados/")
    end
  end
end
