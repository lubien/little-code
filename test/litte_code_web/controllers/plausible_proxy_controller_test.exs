defmodule LitteCodeWeb.PlausibleProxyControllerTest do
  # Not async: we mutate a global application env value.
  use LitteCodeWeb.ConnCase, async: false

  @stub_name :plausible_proxy_stub

  setup do
    original = Application.get_env(:litte_code, :plausible_proxy, [])
    Application.put_env(:litte_code, :plausible_proxy, plug: {Req.Test, @stub_name})
    on_exit(fn -> Application.put_env(:litte_code, :plausible_proxy, original) end)
    :ok
  end

  describe "GET /js/:filename (script proxy)" do
    test "streams the upstream tracker script back with cache headers", %{conn: conn} do
      Req.Test.stub(@stub_name, fn plug_conn ->
        assert plug_conn.request_path == "/js/script.js"

        plug_conn
        |> Plug.Conn.put_resp_header("cache-control", "public, max-age=3600")
        |> Plug.Conn.put_resp_content_type("application/javascript")
        |> Plug.Conn.send_resp(200, "console.log('plausible');")
      end)

      conn = get(conn, ~p"/js/script.js")

      assert response(conn, 200) =~ "plausible"
      assert get_resp_header(conn, "cache-control") == ["public, max-age=3600"]

      assert get_resp_header(conn, "content-type") == ["application/javascript; charset=utf-8"]
    end

    test "rejects filenames that don't look like the Plausible tracker", %{conn: conn} do
      # No upstream stub — we want to confirm we never even attempt the fetch.
      conn = get(conn, "/js/evil-payload.js")
      assert response(conn, 404)
    end

    test "returns 502 when upstream is unreachable", %{conn: conn} do
      Req.Test.stub(@stub_name, fn plug_conn ->
        Req.Test.transport_error(plug_conn, :timeout)
      end)

      conn = get(conn, ~p"/js/script.js")
      assert response(conn, 502) =~ "upstream unavailable"
    end
  end

  describe "POST /api/event (event proxy)" do
    test "forwards the JSON body and returns the upstream status", %{conn: conn} do
      test_pid = self()

      Req.Test.stub(@stub_name, fn plug_conn ->
        assert plug_conn.request_path == "/api/event"
        assert plug_conn.method == "POST"

        {:ok, body, plug_conn} = Plug.Conn.read_body(plug_conn)
        payload = Jason.decode!(body)
        send(test_pid, {:forwarded, payload, plug_conn.req_headers})

        Plug.Conn.send_resp(plug_conn, 202, "")
      end)

      payload = %{
        "name" => "pageview",
        "url" => "https://little-co.de/",
        "domain" => "little-co.de"
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("user-agent", "MyBrowser/1.0")
        |> post(~p"/api/event", Jason.encode!(payload))

      assert response(conn, 202)

      assert_receive {:forwarded, ^payload, headers}
      assert {"user-agent", "MyBrowser/1.0"} in headers
      # X-Forwarded-For should include the peer address.
      assert Enum.any?(headers, fn {k, v} -> k == "x-forwarded-for" and v != "" end)
    end

    test "forwards raw text/plain beacons (navigator.sendBeacon path)", %{conn: conn} do
      # Regression: sendBeacon uses `text/plain` to avoid CORS preflight,
      # which means Plug.Parsers never populates `body_params`. The old
      # controller crashed on `Jason.encode!(%Plug.Conn.Unfetched{})` here.
      test_pid = self()

      Req.Test.stub(@stub_name, fn plug_conn ->
        {:ok, body, plug_conn} = Plug.Conn.read_body(plug_conn)
        send(test_pid, {:forwarded, body, plug_conn.req_headers})
        Plug.Conn.send_resp(plug_conn, 202, "")
      end)

      raw = ~s({"n":"pageview","u":"https://little-co.de/","d":"little-co.de"})

      conn =
        conn
        |> put_req_header("content-type", "text/plain")
        |> post(~p"/api/event", raw)

      assert response(conn, 202)
      assert_receive {:forwarded, ^raw, headers}
      assert {"content-type", "text/plain"} in headers
    end

    test "handles an empty POST body without crashing", %{conn: conn} do
      Req.Test.stub(@stub_name, fn plug_conn ->
        Plug.Conn.send_resp(plug_conn, 202, "")
      end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/event", "")

      assert response(conn, 202)
    end

    test "returns 202 when the upstream errors — analytics never break the site",
         %{conn: conn} do
      Req.Test.stub(@stub_name, fn plug_conn ->
        Req.Test.transport_error(plug_conn, :timeout)
      end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/event", Jason.encode!(%{"name" => "pageview"}))

      assert response(conn, 202)
    end
  end
end
