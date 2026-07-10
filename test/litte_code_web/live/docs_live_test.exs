defmodule LitteCodeWeb.DocsLiveTest do
  use LitteCodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders API examples", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/docs")

    assert html =~ "API"
    assert html =~ "POST /api/links"
    assert html =~ "X-RateLimit-Limit"
    # Custom slugs section mentions the admin key + self-host repo.
    assert html =~ "ADMIN_KEY"
    assert html =~ "github.com/lubien/little-code"
  end

  test "docs page is reachable from the header", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ ~s(href="/docs")
  end
end
