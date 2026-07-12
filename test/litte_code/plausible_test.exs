defmodule LitteCode.PlausibleTest do
  # Not async — we swap the module-wide config to point Req at a test stub.
  use ExUnit.Case, async: false

  alias LitteCode.Plausible

  @stub_name :plausible_backend_stub

  setup do
    original = Application.get_env(:litte_code, Plausible)

    Application.put_env(:litte_code, Plausible,
      domain: "little-co.de",
      events_url: "https://plausible.test/api/event",
      req_options: [plug: {Req.Test, @stub_name}]
    )

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:litte_code, Plausible)
      else
        Application.put_env(:litte_code, Plausible, original)
      end
    end)

    :ok
  end

  describe "send_event/1" do
    test "POSTs a Plausible-shaped payload and returns :ok on 202" do
      test_pid = self()

      Req.Test.stub(@stub_name, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:sent, Jason.decode!(body), conn.req_headers})
        Plug.Conn.send_resp(conn, 202, "")
      end)

      assert :ok =
               Plausible.send_event(
                 name: "Redirect",
                 url: "https://little-co.de/l/abc12",
                 remote_ip: {203, 0, 113, 4},
                 user_agent: "curl/8.0",
                 props: %{"kind" => "hash"}
               )

      assert_receive {:sent, payload, headers}, 500

      assert %{
               "name" => "Redirect",
               "url" => "https://little-co.de/l/abc12",
               "domain" => "little-co.de",
               "props" => %{"kind" => "hash"}
             } = payload

      assert {"user-agent", "curl/8.0"} in headers
      assert {"x-forwarded-for", "203.0.113.4"} in headers
    end

    test "swallows a non-2xx response without crashing" do
      Req.Test.stub(@stub_name, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

      # Doesn't raise. Return value can be either :ok or {:error, _} — we just
      # care that analytics failures don't propagate.
      assert Plausible.send_event(url: "https://little-co.de/l/abc12") in [:ok, nil]
    end

    test "swallows transport errors" do
      Req.Test.stub(@stub_name, fn conn -> Req.Test.transport_error(conn, :timeout) end)

      assert Plausible.send_event(url: "https://little-co.de/l/abc12") in [:ok, nil]
    end
  end

  describe "track/1" do
    test "returns :ok immediately without blocking on the upstream" do
      # Share stubs with any process the task supervisor might spawn.
      Req.Test.set_req_test_to_shared()

      Req.Test.stub(@stub_name, fn conn ->
        # Simulate slow upstream. If `track/1` were sync this would time out.
        Process.sleep(200)
        Plug.Conn.send_resp(conn, 202, "")
      end)

      start = System.monotonic_time(:millisecond)
      assert :ok = Plausible.track(url: "https://little-co.de/l/abc12")
      elapsed = System.monotonic_time(:millisecond) - start

      # `track/1` must not wait for the (fake, slow) upstream.
      assert elapsed < 50

      # Give the task a moment to finish so we don't leak logs into the next test.
      Process.sleep(300)
    end

    test "no-op when the tracker is not configured" do
      Application.put_env(:litte_code, Plausible, [])

      # No stub registered — calling anything would raise. It should never call.
      assert :ok = Plausible.track(url: "https://little-co.de/l/abc12")
    end
  end
end
