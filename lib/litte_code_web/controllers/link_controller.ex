defmodule LitteCodeWeb.LinkController do
  use LitteCodeWeb, :controller

  alias LitteCode.Links
  alias LitteCode.Plausible

  @doc "GET /l/:hash — redirect via the auto-generated hash."
  def show(conn, %{"hash" => hash}) do
    redirect_or_404(conn, Links.get_by_hash(hash))
  end

  @doc "GET /c/:slug — redirect via a custom admin-created slug."
  def show_slug(conn, %{"slug" => slug}) do
    redirect_or_404(conn, Links.get_by_slug(slug))
  end

  defp redirect_or_404(conn, nil) do
    conn
    |> put_status(:not_found)
    |> put_view(LitteCodeWeb.ErrorHTML)
    |> render(:"404")
  end

  defp redirect_or_404(conn, link) do
    # Track the view. Increment is atomic in the DB — no need to reload.
    _ = Links.increment_views(link)

    # Fire a Plausible event *asynchronously* so the redirect isn't
    # slowed down or blocked by upstream latency / outages. QR scanners
    # and curl users never load our HTML, so this is the only chance to
    # attribute the visit in analytics.
    Plausible.track(
      name: "Redirect",
      url: current_url(conn),
      referrer: get_req_header(conn, "referer") |> List.first(),
      user_agent: get_req_header(conn, "user-agent") |> List.first(),
      remote_ip: conn.remote_ip,
      props: %{
        "shortlink" => shortlink_display(link),
        "target_host" => target_host(link.url),
        "kind" => if(link.slug, do: "slug", else: "hash")
      }
    )

    # 302 (Found) so browsers keep hitting us — otherwise view counts
    # would be under-reported after a cache-friendly 301.
    redirect(conn, external: link.url)
  end

  defp shortlink_display(%{slug: slug}) when is_binary(slug), do: "/c/" <> slug
  defp shortlink_display(%{hash: hash}), do: "/l/" <> hash

  defp target_host(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) -> host
      _ -> "unknown"
    end
  end
end
