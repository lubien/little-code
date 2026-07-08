defmodule LitteCodeWeb.HealthController do
  @moduledoc """
  Lightweight readiness endpoint used by Fly.io's blue/green health checks
  and any external uptime monitors. Returns 200 as soon as the endpoint is
  serving HTTP — that implies the app supervision tree started cleanly.
  """
  use LitteCodeWeb, :controller

  def show(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "ok\n")
  end
end
