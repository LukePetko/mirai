defmodule Mirai.RuntimeApiTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  @token "runtime-test-token-that-is-long-enough"

  defmodule ApiAutomation do
  end

  setup do
    runtime =
      start_supervised!({Mirai.Runtime, name: :runtime_api_test, automations: [ApiAutomation]})

    Process.register(self(), ApiAutomation)

    on_exit(fn ->
      if Process.whereis(ApiAutomation) == self(), do: Process.unregister(ApiAutomation)
    end)

    opts = Mirai.Runtime.Api.init(token: @token, runtime: runtime)
    %{opts: opts, runtime: runtime}
  end

  test "rejects snapshot and health requests without the bearer token", %{opts: opts} do
    Enum.each(["/v1/snapshot", "/health"], fn path ->
      conn =
        conn(:get, path)
        |> Mirai.Runtime.Api.call(opts)

      assert conn.status == 401
      assert Jason.decode!(conn.resp_body) == %{"error" => "unauthorized"}
    end)
  end

  test "rejects duplicate authorization headers", %{opts: opts} do
    conn = %{
      conn(:get, "/v1/snapshot")
      | req_headers: [
          {"authorization", "Bearer #{@token}"},
          {"authorization", "Bearer #{@token}"}
        ]
    }

    conn = Mirai.Runtime.Api.call(conn, opts)
    assert conn.status == 401
  end

  test "returns the manager's versioned snapshot contract", %{opts: opts, runtime: runtime} do
    Mirai.Runtime.record_action(
      ApiAutomation,
      "light.toggle",
      "light.hall_light",
      33,
      runtime
    )

    conn =
      conn(:get, "/v1/snapshot")
      |> put_req_header("authorization", "Bearer #{@token}")
      |> Mirai.Runtime.Api.call(opts)

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]

    body = Jason.decode!(conn.resp_body)

    assert Map.keys(body) |> Enum.sort() ==
             ~w(automations capturedAt deployment events homeAssistant metrics runtime source)
             |> Enum.sort()

    assert body["source"] == "runtime"
    assert body["runtime"]["status"] in ~w(online degraded offline)
    assert Map.has_key?(body["homeAssistant"], "cachedStates")
    assert is_number(body["metrics"]["eventsPerMinute"])

    assert [automation] = body["automations"]

    assert Map.keys(automation) |> Enum.sort() ==
             ~w(durationMs id lastRunAt name status target) |> Enum.sort()

    assert automation["status"] in ~w(running warning idle stopped)
    assert automation["durationMs"] == 33

    assert [event] = body["events"]

    assert Map.keys(event) |> Enum.sort() ==
             ~w(id level message occurredAt source) |> Enum.sort()

    assert event["level"] in ~w(success warning info error)
    refute conn.resp_body =~ @token
  end

  test "returns health for authenticated callers", %{opts: opts} do
    conn =
      conn(:get, "/health")
      |> put_req_header("authorization", "Bearer #{@token}")
      |> Mirai.Runtime.Api.call(opts)

    assert conn.status == 200
    assert Jason.decode!(conn.resp_body) == %{"status" => "ok"}
  end

  test "returns not found for unknown paths", %{opts: opts} do
    conn =
      conn(:get, "/unknown")
      |> put_req_header("authorization", "Bearer #{@token}")
      |> Mirai.Runtime.Api.call(opts)

    assert conn.status == 404
  end
end
