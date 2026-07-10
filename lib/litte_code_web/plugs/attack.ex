defmodule LitteCodeWeb.Plugs.Attack do
  @moduledoc """
  Rate-limiting and abuse prevention using `PlugAttack`.

  * `/up` is allow-listed — Fly.io health checks never count.
  * `POST /api/links` is capped at 30 shortens/min/IP so the JSON API
    can't be used to flood the database.
  * Every other request is capped at 60/min/IP.

  Responses include `X-RateLimit-Limit`, `X-RateLimit-Remaining`,
  `X-RateLimit-Reset`, and (on 429s) `Retry-After` headers so well-behaved
  API clients can back off.
  """

  use PlugAttack

  import Plug.Conn

  # Short-circuit: the Fly.io health check hits `/up` every 30s from many
  # proxy IPs; letting it flow through the throttler would either count
  # against a legitimate visitor's budget or (worse) start returning 429s
  # once Fly's proxy pool gets busy. `allow` returns `{:allow, _}` which
  # stops rule evaluation, so `/up` never touches the throttle counter.
  rule "allow health check", conn do
    allow(conn.request_path == "/up")
  end

  # API create bucket: 30 shortens/min/IP. Bots hitting the JSON API get
  # cut off long before they can build up a link database. Matched before
  # the generic per-IP throttle so it also acts as a hard cap on this
  # specific route.
  rule "throttle api link creates", conn do
    if conn.method == "POST" and conn.request_path == "/api/links" do
      throttle({:api_links_create, conn.remote_ip},
        period: 60_000,
        limit: 30,
        storage: {PlugAttack.Storage.Ets, LitteCodeWeb.Plugs.Attack.Storage}
      )
    end
  end

  rule "throttle by ip", conn do
    throttle(conn.remote_ip,
      period: 60_000,
      limit: 60,
      storage: {PlugAttack.Storage.Ets, LitteCodeWeb.Plugs.Attack.Storage}
    )
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

  # Adds the standard rate-limit trio plus a `Retry-After` (seconds
  # until the current bucket resets) so well-behaved clients back off.
  defp add_throttling_headers(conn, data) do
    reset_ms = data[:expires_at]
    reset_s = div(reset_ms, 1_000)
    retry_after = max(div(reset_ms - System.system_time(:millisecond), 1_000), 0)

    conn
    |> put_resp_header("x-ratelimit-limit", to_string(data[:limit]))
    |> put_resp_header("x-ratelimit-remaining", to_string(data[:remaining]))
    |> put_resp_header("x-ratelimit-reset", to_string(reset_s))
    |> put_resp_header("retry-after", to_string(retry_after))
  end
end
