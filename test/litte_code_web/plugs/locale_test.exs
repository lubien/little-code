defmodule LitteCodeWeb.Plugs.LocaleTest do
  use LitteCodeWeb.ConnCase, async: true

  alias LitteCodeWeb.Plugs.Locale

  defp with_session(conn) do
    conn
    |> Plug.Test.init_test_session(%{})
  end

  test "defaults to English with no session and no Accept-Language" do
    conn =
      :get
      |> Phoenix.ConnTest.build_conn("/")
      |> with_session()
      |> Locale.call([])

    assert conn.assigns.locale == "en"
    assert Plug.Conn.get_session(conn, :locale) == "en"
  end

  test "picks up locale from the session when set" do
    conn =
      :get
      |> Phoenix.ConnTest.build_conn("/")
      |> with_session()
      |> Plug.Conn.put_session(:locale, "pt_BR")
      |> Locale.call([])

    assert conn.assigns.locale == "pt_BR"
  end

  test "falls back to Accept-Language when no session locale is set" do
    conn =
      :get
      |> Phoenix.ConnTest.build_conn("/")
      |> Plug.Conn.put_req_header("accept-language", "pt-BR,pt;q=0.9,en;q=0.7")
      |> with_session()
      |> Locale.call([])

    assert conn.assigns.locale == "pt_BR"
    assert Plug.Conn.get_session(conn, :locale) == "pt_BR"
  end

  test "ignores unsupported session locales and re-detects" do
    conn =
      :get
      |> Phoenix.ConnTest.build_conn("/")
      |> Plug.Conn.put_req_header("accept-language", "pt-BR")
      |> with_session()
      |> Plug.Conn.put_session(:locale, "bogus")
      |> Locale.call([])

    assert conn.assigns.locale == "pt_BR"
  end
end
