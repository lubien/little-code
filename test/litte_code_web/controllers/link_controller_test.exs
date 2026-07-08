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
end
