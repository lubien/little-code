defmodule LitteCodeWeb.LinkControllerTest do
  # Not async — the Plausible tracking stub is process-scoped and we
  # want the ownership to survive the async task the controller spawns.
  use LitteCodeWeb.ConnCase, async: false

  alias LitteCode.Links
  alias LitteCode.Plausible

  @plausible_stub :link_controller_plausible_stub

  setup do
    original = Application.get_env(:litte_code, Plausible)

    Application.put_env(:litte_code, Plausible,
      domain: "little-co.de",
      events_url: "https://plausible.test/api/event",
      req_options: [plug: {Req.Test, @plausible_stub}]
    )

    Req.Test.set_req_test_to_shared()

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:litte_code, Plausible)
      else
        Application.put_env(:litte_code, Plausible, original)
      end
    end)

    :ok
  end

  test "GET /l/:hash redirects, bumps view count, and fires a Plausible event",
       %{conn: conn} do
    test_pid = self()

    Req.Test.stub(@plausible_stub, fn plug_conn ->
      {:ok, body, plug_conn} = Plug.Conn.read_body(plug_conn)
      send(test_pid, {:plausible, Jason.decode!(body)})
      Plug.Conn.send_resp(plug_conn, 202, "")
    end)

    {:ok, link} = Links.create_link(%{"url" => "https://example.com/hello"})

    conn = get(conn, ~p"/l/#{link.hash}")
    assert redirected_to(conn, 302) == "https://example.com/hello"
    assert Links.get_by_hash(link.hash).views == 1

    assert_receive {:plausible, event}, 500

    assert %{
             "name" => "Redirect",
             "domain" => "little-co.de",
             "props" => %{
               "shortlink" => shortlink,
               "target_host" => "example.com",
               "kind" => "hash"
             }
           } = event

    assert shortlink == "/l/" <> link.hash
  end

  test "GET /l/:hash returns 404 for an unknown hash", %{conn: conn} do
    conn = get(conn, ~p"/l/does-not-exist")
    assert response(conn, 404)
  end

  test "GET /c/:slug redirects, tracks views, and fires a Plausible event with kind=slug",
       %{conn: conn} do
    test_pid = self()

    Req.Test.stub(@plausible_stub, fn plug_conn ->
      {:ok, body, plug_conn} = Plug.Conn.read_body(plug_conn)
      send(test_pid, {:plausible, Jason.decode!(body)})
      Plug.Conn.send_resp(plug_conn, 202, "")
    end)

    {:ok, link} =
      Links.create_link(
        %{"url" => "https://example.com/via-slug", "slug" => "via-slug"},
        admin?: true
      )

    conn = get(conn, ~p"/c/#{link.slug}")
    assert redirected_to(conn, 302) == "https://example.com/via-slug"
    assert Links.get_by_slug("via-slug").views == 1

    assert_receive {:plausible, event}, 500
    assert event["props"]["kind"] == "slug"
    assert event["props"]["shortlink"] == "/c/via-slug"
  end

  test "GET /c/:slug returns 404 for an unknown slug", %{conn: conn} do
    conn = get(conn, ~p"/c/nope-nada")
    assert response(conn, 404)
  end
end
