defmodule LitteCodeWeb.LinkControllerTest do
  use LitteCodeWeb.ConnCase, async: true

  alias LitteCode.Links

  test "GET /l/:hash redirects to the target URL and tracks the view", %{conn: conn} do
    {:ok, link} = Links.create_link(%{"url" => "https://example.com/hello"})

    conn = get(conn, ~p"/l/#{link.hash}")
    assert redirected_to(conn, 302) == "https://example.com/hello"

    assert Links.get_by_hash(link.hash).views == 1
  end

  test "GET /l/:hash returns 404 for an unknown hash", %{conn: conn} do
    conn = get(conn, ~p"/l/does-not-exist")
    assert response(conn, 404)
  end

  test "GET /c/:slug redirects and tracks views", %{conn: conn} do
    {:ok, link} =
      Links.create_link(
        %{"url" => "https://example.com/via-slug", "slug" => "via-slug"},
        admin?: true
      )

    conn = get(conn, ~p"/c/#{link.slug}")
    assert redirected_to(conn, 302) == "https://example.com/via-slug"

    assert Links.get_by_slug("via-slug").views == 1
  end

  test "GET /c/:slug returns 404 for an unknown slug", %{conn: conn} do
    conn = get(conn, ~p"/c/nope-nada")
    assert response(conn, 404)
  end
end
