defmodule LitteCodeWeb.Plugs.AttackTest do
  # Not async: PlugAttack.Storage.Ets is shared global state.
  use LitteCodeWeb.ConnCase, async: false

  @storage LitteCodeWeb.Plugs.Attack.Storage

  setup do
    # Wipe the throttle counters before *and* after each test so that
    # (a) each test starts from zero and (b) other test files sharing
    # the same ETS table aren't left with a spent bucket for 127.0.0.1.
    PlugAttack.Storage.Ets.clean(@storage)
    on_exit(fn -> PlugAttack.Storage.Ets.clean(@storage) end)
    :ok
  end

  test "GET /up never gets throttled", %{conn: conn} do
    for _ <- 1..80 do
      resp = get(build_conn(), ~p"/up")
      assert resp.status == 200
    end

    _ = conn
  end

  test "other paths still hit the 60/min per-IP throttle" do
    # First 60 requests are allowed.
    for _ <- 1..60 do
      resp = get(build_conn(), ~p"/")
      assert resp.status == 200
    end

    # The 61st request from the same IP is blocked.
    blocked = get(build_conn(), ~p"/")
    assert blocked.status == 429
  end
end
