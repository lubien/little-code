defmodule LitteCodeWeb.RateLimit do
  @moduledoc """
  Thin wrapper around `PlugAttack` for rate-limiting outside of the
  regular plug pipeline (e.g. LiveView event handlers).
  """

  @storage {PlugAttack.Storage.Ets, LitteCodeWeb.Plugs.Attack.Storage}

  @doc """
  Increments the counter for `key` in the shared PlugAttack storage.

  Returns `:ok` when the caller is under the limit and `{:error, :rate_limited}`
  once the limit has been reached for the current window.
  """
  @spec check(term(), keyword()) :: :ok | {:error, :rate_limited}
  def check(key, opts) do
    opts = Keyword.put_new(opts, :storage, @storage)

    case PlugAttack.Rule.throttle(key, opts) do
      {:allow, _data} -> :ok
      {:block, _data} -> {:error, :rate_limited}
      nil -> :ok
    end
  end
end
