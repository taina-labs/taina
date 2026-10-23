defmodule Ypy.HandleTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Ypy.Handle

  @charset ~c"abcdefghijklmnopqrstuvwxyz0123456789._-"

  test "parses the golden handle into its parts" do
    assert Handle.parse("maria@tekoa.example.org") ==
             {:ok, %{nome: "maria", tekoa: "tekoa.example.org"}}
  end

  test "normalize trims and downcases without validating" do
    assert Handle.normalize("  MARIA@Tekoa.Example.ORG ") == "maria@tekoa.example.org"
  end

  test "normalize then parse is the golden roundtrip" do
    assert Handle.parse(Handle.normalize("  MARIA@Tekoa.Example.ORG ")) ==
             {:ok, %{nome: "maria", tekoa: "tekoa.example.org"}}
  end

  test "parse does not normalize" do
    assert Handle.parse("MARIA@tekoa.example.org") == {:error, :invalid}
    assert Handle.parse(" maria@tekoa.example.org") == {:error, :invalid}
  end

  test "rejects the malformed shapes" do
    for handle <- [
          "",
          "   ",
          "maria tekoa",
          "@tekoa.example.org",
          "maria@",
          "maria@@tekoa.example.org",
          "maria@tekoa.example.org.",
          "maria@.tekoa.example.org",
          "maria@-tekoa.example.org",
          "maria@tekoa-.example.org",
          "maria@teko_a.example.org",
          "maria@tekoa.example.org:8443",
          "maria+extra@tekoa.example.org",
          "m@r@tekoa.example.org",
          String.duplicate("a", 250) <> "@t.co"
        ] do
      assert {:error, :invalid} == Handle.parse(handle),
             "expected #{inspect(handle)} to be invalid"

      refute Handle.valid?(handle)
    end
  end

  test "accepts a single-label domain (a box on the LAN)" do
    assert Handle.valid?("maria@box.local")
  end

  test "valid_domain? shares the domain grammar" do
    for domain <- ["tekoa.example.org", "box.local", "a-b.io"] do
      assert Handle.valid_domain?(domain)
    end

    for domain <- [
          "",
          ".tekoa.org",
          "tekoa.example.org.",
          "-tekoa.org",
          "tekoa..org",
          "teko_a.org"
        ] do
      refute Handle.valid_domain?(domain), "expected #{inspect(domain)} to be invalid"
    end
  end

  property "a built handle parses back to the parts that built it" do
    check all(
            nome <- nome(),
            tekoa <- domain()
          ) do
      handle = nome <> "@" <> tekoa

      assert {:ok, %{nome: ^nome, tekoa: ^tekoa}} = Handle.parse(handle)
      assert Handle.valid?(handle)
    end
  end

  defp nome do
    gen all(
          head <- StreamData.member_of(@charset),
          tail <- StreamData.string(@charset, max_length: 20)
        ) do
      <<head>> <> tail
    end
  end

  defp domain do
    gen all(labels <- StreamData.list_of(label(), min_length: 1, max_length: 3)) do
      Enum.join(labels, ".")
    end
  end

  defp label do
    gen all(
          first <- StreamData.member_of(~c"abcdefghijklmnopqrstuvwxyz0123456789"),
          middle <-
            StreamData.list_of(
              StreamData.member_of(~c"abcdefghijklmnopqrstuvwxyz0123456789-"),
              max_length: 8
            ),
          last <- StreamData.member_of(~c"abcdefghijklmnopqrstuvwxyz0123456789")
        ) do
      List.to_string([first | middle] ++ [last])
    end
  end
end
