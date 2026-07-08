defmodule LitteCodeWeb.HealthControllerTest do
  use LitteCodeWeb.ConnCase, async: true

  test "GET /up returns 200 with a plain-text body", %{conn: conn} do
    conn = get(conn, ~p"/up")
    assert response(conn, 200) == "ok\n"
    assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
  end
end
