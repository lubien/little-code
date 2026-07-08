defmodule LitteCodeWeb.LinkController do
  use LitteCodeWeb, :controller

  alias LitteCode.Links

  def show(conn, %{"hash" => hash}) do
    case Links.get_by_hash(hash) do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_view(LitteCodeWeb.ErrorHTML)
        |> render(:"404")

      link ->
        # Track the view. Increment is atomic in the DB — no need to reload.
        _ = Links.increment_views(link)

        # 302 (Found) so browsers keep hitting us — otherwise view counts
        # would be under-reported after a cache-friendly 301.
        redirect(conn, external: link.url)
    end
  end
end
