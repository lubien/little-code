defmodule LitteCode.Captcha do
  @moduledoc """
  A tiny, stateless math CAPTCHA.

  A challenge is a small arithmetic question (e.g. "3 + 5"). The
  expected answer is signed with a Phoenix `Plug.Crypto` token so we
  don't need to persist it server-side — the browser sends the token
  and answer back, and we verify both together.

  Tokens expire after `@max_age` seconds to prevent replay.
  """

  alias Phoenix.Token

  @max_age 60 * 15
  @salt "little-code captcha v1"

  @type challenge :: %{question: String.t(), token: String.t()}

  @doc """
  Generates a fresh challenge with a signed token.
  """
  @spec new() :: challenge()
  def new do
    {a, b, op, answer} = random_problem()
    token = Token.sign(endpoint(), @salt, answer)

    %{question: "#{a} #{op} #{b}", token: token}
  end

  @doc """
  Verifies the user's answer against a signed token.
  Returns `:ok` on match, `{:error, reason}` otherwise.
  """
  @spec verify(String.t() | nil, String.t() | nil) :: :ok | {:error, atom()}
  def verify("", _answer), do: {:error, :missing}
  def verify(_token, ""), do: {:error, :missing}

  def verify(token, answer) when is_binary(token) and is_binary(answer) do
    case Token.verify(endpoint(), @salt, token, max_age: @max_age) do
      {:ok, expected} ->
        case Integer.parse(String.trim(answer)) do
          {^expected, ""} -> :ok
          _ -> {:error, :incorrect}
        end

      {:error, :expired} ->
        {:error, :expired}

      {:error, _reason} ->
        # `:invalid` (tampered/garbage) and `:missing` (nil token) both
        # boil down to "user needs a fresh challenge".
        {:error, :incorrect}
    end
  end

  def verify(_token, _answer), do: {:error, :missing}

  defp random_problem do
    a = :rand.uniform(9) + 1
    b = :rand.uniform(9) + 1

    case Enum.random([:add, :sub]) do
      :add -> {a, b, "+", a + b}
      :sub when a >= b -> {a, b, "-", a - b}
      :sub -> {b, a, "-", b - a}
    end
  end

  defp endpoint, do: LitteCodeWeb.Endpoint
end
