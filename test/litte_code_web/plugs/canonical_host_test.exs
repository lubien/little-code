defmodule LitteCodeWeb.Plugs.CanonicalHostTest do
  # Not async: we toggle a global application env value.
  use LitteCodeWeb.ConnCase, async: false

  alias LitteCodeWeb.Plugs.CanonicalHost

  setup do
    original = Application.get_env(:litte_code, CanonicalHost, [])
    on_exit(fn -> Application.put_env(:litte_code, CanonicalHost, original) end)
    :ok
  end

  defp enable! do
    Application.put_env(:litte_code, CanonicalHost, enabled: true)
  end

  defp conn_with_host(host, path \\ "/", query \\ "") do
    :get
    |> Phoenix.ConnTest.build_conn(path <> if(query == "", do: "", else: "?" <> query))
    |> Map.put(:host, host)
    |> Map.put(:query_string, query)
    |> Map.put(:request_path, path)
  end

  test "is a no-op when disabled (default)" do
    # Not enabled — nothing should happen even on a foreign host.
    conn = conn_with_host("www.example.com") |> CanonicalHost.call([])
    refute conn.halted
    assert conn.status == nil
  end

  test "redirects off-canonical hosts to PHX_HOST with a 301" do
    enable!()

    conn =
      "www.little-co.de"
      |> conn_with_host("/some/path", "a=1&b=2")
      |> CanonicalHost.call([])

    assert conn.halted
    assert conn.status == 301

    [location] = Plug.Conn.get_resp_header(conn, "location")
    # Endpoint URL in tests uses http://localhost; the plug reads that config.
    assert location =~ "://localhost/some/path?a=1&b=2"
  end

  test "leaves requests on the canonical host alone" do
    enable!()

    conn = conn_with_host("localhost") |> CanonicalHost.call([])

    refute conn.halted
    assert conn.status == nil
  end

  test "leaves requests coming in on a raw IP alone (LB / health checks)" do
    enable!()

    conn = conn_with_host("10.0.0.42") |> CanonicalHost.call([])

    refute conn.halted
    assert conn.status == nil
  end

  test "canonical comparison is case-insensitive" do
    enable!()

    conn = conn_with_host("LOCALHOST") |> CanonicalHost.call([])

    refute conn.halted
  end

  test "preserves the request path when there's no query string" do
    enable!()

    conn =
      "wrong-host.example"
      |> conn_with_host("/l/abcde")
      |> CanonicalHost.call([])

    assert conn.status == 301
    [location] = Plug.Conn.get_resp_header(conn, "location")
    assert String.ends_with?(location, "/l/abcde")
    refute location =~ "?"
  end
end
