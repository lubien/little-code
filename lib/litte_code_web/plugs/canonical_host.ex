defmodule LitteCodeWeb.Plugs.CanonicalHost do
  @moduledoc """
  Redirects any request whose `Host` header does not match the endpoint's
  configured canonical host to the canonical host with a 301, preserving
  scheme, path, and query string.

  Useful in production for consolidating traffic on a single hostname
  (e.g. redirecting `www.little-co.de` and platform-provided hostnames
  like `little-code.fly.dev` to `little-co.de`).

  ## Configuration

      config :litte_code, LitteCodeWeb.Plugs.CanonicalHost, enabled: true

  The plug is disabled by default so it stays out of the way in dev and
  test. In prod, `config/runtime.exs` flips it on.

  Requests coming in on raw IP addresses or `localhost` are left alone —
  those are typically internal load balancer / health-check traffic.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if enabled?() and should_redirect?(conn) do
      redirect_to_canonical(conn)
    else
      conn
    end
  end

  defp enabled? do
    :litte_code
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:enabled, false)
  end

  defp should_redirect?(%Plug.Conn{host: host}) do
    canonical = canonical_host()

    canonical != nil and
      String.downcase(host) != String.downcase(canonical) and
      not ip_or_localhost?(host)
  end

  defp canonical_host do
    case LitteCodeWeb.Endpoint.config(:url) do
      config when is_list(config) -> Keyword.get(config, :host)
      _ -> nil
    end
  end

  # Don't redirect internal health-check / LB traffic that arrives via
  # a raw IP or the loopback name.
  defp ip_or_localhost?(host) do
    host in ["localhost", "127.0.0.1", "::1"] or
      match?({:ok, _}, :inet.parse_address(String.to_charlist(host)))
  end

  defp redirect_to_canonical(conn) do
    url_config = LitteCodeWeb.Endpoint.config(:url) || []
    scheme = url_config[:scheme] || "https"
    port = url_config[:port]
    host = canonical_host()

    port_suffix =
      cond do
        scheme == "https" and port in [nil, 443] -> ""
        scheme == "http" and port in [nil, 80] -> ""
        true -> ":#{port}"
      end

    query = if conn.query_string in [nil, ""], do: "", else: "?#{conn.query_string}"
    location = "#{scheme}://#{host}#{port_suffix}#{conn.request_path}#{query}"

    conn
    |> put_resp_header("location", location)
    |> put_resp_content_type("text/plain")
    |> send_resp(301, "Moved Permanently: #{location}\n")
    |> halt()
  end
end
