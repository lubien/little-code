defmodule LitteCodeWeb.RemoteIpTest do
  # End-to-end check: hit a real endpoint with the Fly forwarded headers
  # and confirm rate-limit buckets are keyed by the real client IP, not
  # by the (in tests: loopback) TCP peer.
  use LitteCodeWeb.ConnCase, async: false

  @storage LitteCodeWeb.Plugs.Attack.Storage

  setup do
    PlugAttack.Storage.Ets.clean(@storage)
    on_exit(fn -> PlugAttack.Storage.Ets.clean(@storage) end)
    :ok
  end

  defp post_json(conn, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(body))
  end

  test "different Fly-Client-IP values are throttled independently" do
    # Fill the whole 30/min bucket from one fake client IP.
    for _ <- 1..30 do
      resp =
        build_conn()
        |> put_req_header("fly-client-ip", "203.0.113.10")
        |> post_json(~p"/api/links", %{"url" => "https://example.com"})

      assert resp.status == 201
    end

    # 31st from the *same* client → 429.
    blocked =
      build_conn()
      |> put_req_header("fly-client-ip", "203.0.113.10")
      |> post_json(~p"/api/links", %{"url" => "https://example.com"})

    assert blocked.status == 429

    # A different Fly-Client-IP starts from a fresh bucket → 201.
    fresh =
      build_conn()
      |> put_req_header("fly-client-ip", "198.51.100.7")
      |> post_json(~p"/api/links", %{"url" => "https://example.com"})

    assert fresh.status == 201
  end

  test "X-Forwarded-For chain is also honored" do
    for _ <- 1..30 do
      resp =
        build_conn()
        |> put_req_header("x-forwarded-for", "203.0.113.42, 172.19.0.1")
        |> post_json(~p"/api/links", %{"url" => "https://example.com"})

      assert resp.status == 201
    end

    blocked =
      build_conn()
      |> put_req_header("x-forwarded-for", "203.0.113.42, 172.19.0.1")
      |> post_json(~p"/api/links", %{"url" => "https://example.com"})

    assert blocked.status == 429
  end
end
