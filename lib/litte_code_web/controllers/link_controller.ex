defmodule LitteCodeWeb.LinkController do
  use LitteCodeWeb, :controller

  alias LitteCode.Links

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

    # 302 (Found) so browsers keep hitting us — otherwise view counts
    # would be under-reported after a cache-friendly 301.
    redirect(conn, external: link.url)
  end
end
