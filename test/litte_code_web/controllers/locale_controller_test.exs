defmodule LitteCodeWeb.LocaleControllerTest do
  use LitteCodeWeb.ConnCase, async: true

  test "POST /locale/:locale sets the session and redirects back", %{conn: conn} do
    conn =
      conn
      |> Plug.Conn.put_req_header("referer", "http://localhost:4000/?tab=shorten")
      |> post(~p"/locale/pt_BR")

    assert redirected_to(conn) == "/?tab=shorten"
    assert get_session(conn, :locale) == "pt_BR"
  end

  test "POST /locale/:locale respects the return_to param over referer", %{conn: conn} do
    conn = post(conn, ~p"/locale/pt_BR", %{"return_to" => "/?tab=qr"})

    assert redirected_to(conn) == "/?tab=qr"
    assert get_session(conn, :locale) == "pt_BR"
  end

  test "falls back to the default locale for unknown codes", %{conn: conn} do
    conn = post(conn, ~p"/locale/pt", %{"return_to" => "/"})

    assert get_session(conn, :locale) == "en"
  end

  test "redirects to / when return_to is missing", %{conn: conn} do
    conn = post(conn, ~p"/locale/en")
    assert redirected_to(conn) == "/"
  end

  test "won't follow off-site return_to URLs", %{conn: conn} do
    conn = post(conn, ~p"/locale/en", %{"return_to" => "https://evil.example.com/"})
    # We keep only the path portion, so this is safe.
    assert redirected_to(conn) == "/"
  end
end
