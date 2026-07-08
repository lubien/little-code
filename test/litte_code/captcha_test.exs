defmodule LitteCode.CaptchaTest do
  use ExUnit.Case, async: true

  alias LitteCode.Captcha

  test "generating and verifying a valid answer succeeds" do
    challenge = Captcha.new()
    [a_str, op, b_str] = String.split(challenge.question, " ")
    {a, ""} = Integer.parse(a_str)
    {b, ""} = Integer.parse(b_str)

    expected =
      case op do
        "+" -> a + b
        "-" -> a - b
      end

    assert Captcha.verify(challenge.token, Integer.to_string(expected)) == :ok
  end

  test "wrong answer returns :incorrect" do
    challenge = Captcha.new()
    assert Captcha.verify(challenge.token, "99999") == {:error, :incorrect}
  end

  test "non-numeric answer returns :incorrect" do
    challenge = Captcha.new()
    assert Captcha.verify(challenge.token, "abc") == {:error, :incorrect}
  end

  test "missing token or answer returns :missing" do
    assert Captcha.verify(nil, "1") == {:error, :missing}
    assert Captcha.verify("abc", nil) == {:error, :missing}
  end

  test "tampered token is rejected" do
    challenge = Captcha.new()
    assert {:error, _} = Captcha.verify(challenge.token <> "x", "1")
  end
end
