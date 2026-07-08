defmodule LitteCodeWeb.Plugs.Attack do
  @moduledoc """
  Rate-limiting and abuse prevention using `PlugAttack`.

  * Every IP is capped at 60 requests / minute across the whole site.
  * Requests aimed at creating a shortened link are further capped at
    10 per minute per IP — that path is the expensive one we want to
    protect from bots.
  """

  use PlugAttack

  import Plug.Conn

  rule "throttle by ip", conn do
    throttle(conn.remote_ip,
      period: 60_000,
      limit: 60,
      storage: {PlugAttack.Storage.Ets, LitteCodeWeb.Plugs.Attack.Storage}
    )
  end

  rule "throttle shorten submissions", conn do
    if conn.method == "POST" and String.starts_with?(conn.request_path, "/shorten") do
      throttle({:shorten, conn.remote_ip},
        period: 60_000,
        limit: 10,
        storage: {PlugAttack.Storage.Ets, LitteCodeWeb.Plugs.Attack.Storage}
      )
    end
  end

  def allow_action(conn, {:throttle, data}, opts) do
    conn
    |> add_throttling_headers(data)
    |> allow_action(true, opts)
  end

  def allow_action(conn, _data, _opts), do: conn

  def block_action(conn, {:throttle, data}, opts) do
    conn
    |> add_throttling_headers(data)
    |> block_action(false, opts)
  end

  def block_action(conn, _data, _opts) do
    conn
    |> send_resp(:too_many_requests, "Too many requests. Please slow down.")
    |> halt()
  end

  defp add_throttling_headers(conn, data) do
    reset = div(data[:expires_at], 1_000)

    conn
    |> put_resp_header("x-ratelimit-limit", to_string(data[:limit]))
    |> put_resp_header("x-ratelimit-remaining", to_string(data[:remaining]))
    |> put_resp_header("x-ratelimit-reset", to_string(reset))
  end
end
