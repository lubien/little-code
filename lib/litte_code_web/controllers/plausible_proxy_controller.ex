defmodule LitteCodeWeb.PlausibleProxyController do
  @moduledoc """
  Reverse-proxies the Plausible analytics tracker so that:

    * The `<script>` served to browsers lives on our own origin (dodges
      most ad-blocker script filter lists).
    * Analytics events are POSTed to our origin and forwarded server-side
      to the upstream Plausible instance.

  Upstream host is configurable via
  `config :litte_code, :plausible_proxy, upstream: "https://..."`,
  which lets us swap it (or point tests at `Req.Test` / `Bypass`).
  """

  use LitteCodeWeb, :controller

  require Logger

  # Only proxy well-formed Plausible tracker filenames — prevents open
  # proxy abuse (`GET /js/../../etc/passwd`, request smuggling, etc.).
  @script_regex ~r/^script(\.[a-z-]+)*\.js$/

  @doc """
  `GET /js/:filename` — fetches the Plausible tracker script and streams
  it back with the upstream's cache headers.
  """
  def script(conn, %{"filename" => filename}) do
    if Regex.match?(@script_regex, filename) do
      request = build_req() |> Req.merge(url: "/js/" <> filename)

      case Req.get(request) do
        {:ok, %Req.Response{status: 200} = resp} ->
          # Use put_resp_header (not put_resp_content_type) so we don't
          # double up the `; charset=utf-8` suffix that upstream already sets.
          conn
          |> put_resp_header(
            "content-type",
            header(resp, "content-type", "application/javascript; charset=utf-8")
          )
          |> put_resp_header(
            "cache-control",
            header(resp, "cache-control", "public, max-age=86400")
          )
          |> send_resp(200, resp.body)

        other ->
          Logger.warning("Plausible script proxy failed: #{inspect(other)}")

          conn
          |> put_resp_content_type("application/javascript")
          |> send_resp(502, "// Plausible script upstream unavailable\n")
      end
    else
      send_resp(conn, 404, "")
    end
  end

  @doc """
  `POST /api/event` — forwards the event JSON to the upstream Plausible
  instance while preserving the client's IP + user-agent so geo/browser
  breakdowns keep working.
  """
  def event(conn, _params) do
    {body, content_type, conn} = fetch_request_body(conn)

    headers = [
      {"content-type", content_type},
      {"user-agent", req_header(conn, "user-agent", "")},
      {"x-forwarded-for", forwarded_for(conn)},
      {"x-forwarded-proto", scheme_string(conn)},
      {"x-forwarded-host", conn.host}
    ]

    request =
      build_req()
      |> Req.merge(url: "/api/event", method: :post, body: body, headers: headers)

    case Req.request(request) do
      {:ok, %Req.Response{status: status, body: response_body}} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(status, IO.iodata_to_binary(response_body || ""))

      {:error, reason} ->
        Logger.warning("Plausible event proxy failed: #{inspect(reason)}")
        # Analytics must never break the site — swallow the error.
        send_resp(conn, 202, "")
    end
  end

  # -- helpers ---------------------------------------------------------

  defp build_req do
    opts =
      Application.get_env(:litte_code, :plausible_proxy, [])
      |> Keyword.put_new(:base_url, "https://devsnorte-plausible.fly.dev")
      |> Keyword.put_new(:receive_timeout, 5_000)
      |> Keyword.put_new(:connect_options, timeout: 3_000)
      |> Keyword.put_new(:decode_body, false)
      |> Keyword.put_new(:retry, false)

    Req.new(opts)
  end

  # `Plug.Parsers` in our endpoint pipeline runs before controllers, so
  # a JSON event body is already parsed into `conn.body_params`. We
  # re-encode it — the round-trip is lossless for Plausible payloads
  # (string keys, JSON-native values). Requests that used a non-JSON
  # content type (e.g. `text/plain` from `navigator.sendBeacon`) never
  # reach a parser: `body_params` stays as `%Plug.Conn.Unfetched{}` and
  # the raw body is still available via `read_body/1`.
  defp fetch_request_body(conn) do
    content_type = req_header(conn, "content-type", "application/json")

    case conn.body_params do
      %Plug.Conn.Unfetched{} ->
        # Body wasn't consumed by any parser (e.g. text/plain beacon).
        # Read it verbatim so we can forward whatever the client sent.
        case Plug.Conn.read_body(conn) do
          {:ok, body, conn} -> {body, content_type, conn}
          _ -> {"", content_type, conn}
        end

      params when is_map(params) and map_size(params) > 0 ->
        # Plug.Parsers successfully parsed a JSON body.
        {Jason.encode!(params), "application/json", conn}

      _ ->
        # Empty body with a recognized content type.
        {"", content_type, conn}
    end
  end

  defp req_header(conn, name, default) do
    case Plug.Conn.get_req_header(conn, name) do
      [value | _] -> value
      _ -> default
    end
  end

  defp header(%Req.Response{headers: headers}, name, default) do
    case Map.get(headers, name) do
      [value | _] -> value
      _ -> default
    end
  end

  defp forwarded_for(conn) do
    # Preserve any existing X-Forwarded-For chain and append this hop's
    # peer address so Plausible still gets the original client.
    existing = req_header(conn, "x-forwarded-for", "")
    peer = conn.remote_ip |> :inet.ntoa() |> to_string()

    case existing do
      "" -> peer
      chain -> chain <> ", " <> peer
    end
  end

  defp scheme_string(%{scheme: :https}), do: "https"
  defp scheme_string(_), do: "http"
end
