defmodule LitteCodeWeb.Api.LinkControllerTest do
  # Not async: the rate-limit test mutates the shared PlugAttack ETS
  # storage and would trip on parallel tests hitting `/api/links`.
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
    |> put_req_header("accept", "application/json")
    |> post(path, Jason.encode!(body))
  end

  describe "POST /api/links" do
    test "creates a link and returns the short URL", %{conn: conn} do
      conn = post_json(conn, ~p"/api/links", %{"url" => "https://example.com/hello"})

      assert %{
               "data" => %{
                 "hash" => hash,
                 "url" => "https://example.com/hello",
                 "short_url" => short_url,
                 "views" => 0,
                 "created_at" => created_at
               }
             } = json_response(conn, 201)

      assert is_binary(hash) and String.length(hash) >= 5
      assert String.ends_with?(short_url, "/l/" <> hash)
      assert is_binary(created_at)

      # `Location` header points at the redirect URL.
      assert [^short_url] = get_resp_header(conn, "location")

      # Rate-limit headers are present on success too, so clients can
      # be nice and pace themselves.
      assert [_] = get_resp_header(conn, "x-ratelimit-limit")
      assert [_] = get_resp_header(conn, "x-ratelimit-remaining")
    end

    test "returns 422 with validation errors for an invalid URL", %{conn: conn} do
      conn = post_json(conn, ~p"/api/links", %{"url" => "not a url"})

      assert %{
               "error" => "validation_failed",
               "details" => %{"url" => [_ | _]}
             } = json_response(conn, 422)
    end

    test "returns 422 when url is missing entirely", %{conn: conn} do
      conn = post_json(conn, ~p"/api/links", %{})

      assert %{
               "error" => "validation_failed",
               "details" => %{"url" => [_ | _]}
             } = json_response(conn, 422)
    end

    test "rejects non-http schemes", %{conn: conn} do
      conn = post_json(conn, ~p"/api/links", %{"url" => "javascript:alert(1)"})

      assert %{"error" => "validation_failed"} = json_response(conn, 422)
    end

    test "actually persists the link", %{conn: conn} do
      conn = post_json(conn, ~p"/api/links", %{"url" => "https://example.com/persisted"})
      %{"data" => %{"hash" => hash}} = json_response(conn, 201)

      assert %LitteCode.Links.Link{url: "https://example.com/persisted"} =
               LitteCode.Links.get_by_hash(hash)
    end

    test "enforces the 30/min rate limit and 429s with Retry-After", %{conn: _conn} do
      # Burn through the whole bucket from a single fake IP.
      for _ <- 1..30 do
        resp = post_json(build_conn(), ~p"/api/links", %{"url" => "https://example.com"})
        assert resp.status == 201
      end

      # The 31st request should be blocked.
      blocked = post_json(build_conn(), ~p"/api/links", %{"url" => "https://example.com"})

      assert blocked.status == 429
      assert [retry_after] = get_resp_header(blocked, "retry-after")
      assert String.to_integer(retry_after) >= 0
    end
  end
end
