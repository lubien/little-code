defmodule LitteCodeWeb.AdminAuth do
  @moduledoc """
  Gates admin-only features (currently: custom slugs) behind a query
  string secret.

  The secret is read at runtime from `config :litte_code, :admin_key`,
  which `config/runtime.exs` sets from the `ADMIN_KEY` env var. When
  the env var is unset or blank, the feature is entirely disabled —
  no query string will unlock it.
  """

  @doc "Whether the server has an admin key configured at all."
  @spec configured?() :: boolean()
  def configured?, do: configured_key() != nil

  @doc """
  Returns `true` when `provided` matches the configured `ADMIN_KEY`
  using a constant-time comparison.

  Returns `false` when:

    * `ADMIN_KEY` is not configured (unset or blank env var).
    * `provided` is nil, blank, or the wrong value.
    * `provided` is not a binary.
  """
  @spec matches?(term()) :: boolean()
  def matches?(provided) do
    with expected when is_binary(expected) <- configured_key(),
         true <- is_binary(provided),
         true <- provided != "" do
      Plug.Crypto.secure_compare(provided, expected)
    else
      _ -> false
    end
  end

  @doc """
  Reads and normalizes the configured admin key. Returns `nil` when it
  is unset or entirely whitespace.
  """
  @spec configured_key() :: String.t() | nil
  def configured_key do
    case Application.get_env(:litte_code, :admin_key) do
      key when is_binary(key) ->
        case String.trim(key) do
          "" -> nil
          trimmed -> trimmed
        end

      _ ->
        nil
    end
  end
end
