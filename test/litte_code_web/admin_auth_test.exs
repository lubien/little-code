defmodule LitteCodeWeb.AdminAuthTest do
  # Not async: mutates a global application env value.
  use ExUnit.Case, async: false

  alias LitteCodeWeb.AdminAuth

  setup do
    original = Application.get_env(:litte_code, :admin_key)
    on_exit(fn -> Application.put_env(:litte_code, :admin_key, original) end)
    :ok
  end

  defp set_key(value), do: Application.put_env(:litte_code, :admin_key, value)

  describe "configured?/0" do
    test "false when unset" do
      Application.delete_env(:litte_code, :admin_key)
      refute AdminAuth.configured?()
    end

    test "false when blank" do
      set_key("")
      refute AdminAuth.configured?()
    end

    test "false when whitespace only" do
      set_key("   \n\t  ")
      refute AdminAuth.configured?()
    end

    test "true when a real key is set" do
      set_key("s3cret")
      assert AdminAuth.configured?()
    end
  end

  describe "matches?/1" do
    test "false when the key isn't configured" do
      Application.delete_env(:litte_code, :admin_key)
      refute AdminAuth.matches?("anything")
    end

    test "false when configured value is blank" do
      set_key("")
      refute AdminAuth.matches?("")
      refute AdminAuth.matches?("anything")
    end

    test "true only for exact match" do
      set_key("s3cret")

      assert AdminAuth.matches?("s3cret")
      refute AdminAuth.matches?("S3cret")
      refute AdminAuth.matches?("s3cret ")
      refute AdminAuth.matches?(" s3cret")
      refute AdminAuth.matches?("wrong")
      refute AdminAuth.matches?("")
      refute AdminAuth.matches?(nil)
      refute AdminAuth.matches?(:atom)
    end
  end
end
