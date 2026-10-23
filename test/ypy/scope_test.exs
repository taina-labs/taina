defmodule Ypy.ScopeTest do
  use ExUnit.Case, async: true

  test "carries who acts and where" do
    scope = %Ypy.Scope{ava: "ava_public_id", tekoa: "tekoa_public_id"}

    assert %Ypy.Scope{ava: "ava_public_id", tekoa: "tekoa_public_id"} == scope
  end

  test "requires both fields" do
    assert_raise ArgumentError, fn -> struct!(Ypy.Scope, ava: "x") end
    assert_raise ArgumentError, fn -> struct!(Ypy.Scope, tekoa: "x") end
  end
end
