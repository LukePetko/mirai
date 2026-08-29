defmodule Mirai.HA.ConnectorRuntimeTest do
  use ExUnit.Case, async: false

  defmodule TrackedAutomation do
    def __mirai_automation__, do: true
  end

  setup do
    runtime =
      start_supervised!(
        {Mirai.Runtime, name: :connector_runtime_test, automations: [TrackedAutomation]}
      )

    Process.register(self(), TrackedAutomation)

    on_exit(fn ->
      if Process.whereis(TrackedAutomation) == self(), do: Process.unregister(TrackedAutomation)
    end)

    %{runtime: runtime}
  end

  test "records a successful action only after Home Assistant acknowledges it", %{
    runtime: runtime
  } do
    timer = Process.send_after(self(), :unused_timeout, 30_000)

    state = %{
      runtime: runtime,
      pending: %{
        42 => %{
          source: TrackedAutomation,
          service: "light.toggle",
          target: "light.hall_light",
          started_at: System.monotonic_time(:millisecond) - 25,
          timer: timer
        }
      }
    }

    message = Jason.encode!(%{type: "result", id: 42, success: true, result: nil})

    assert {:noreply, %{pending: %{}}} =
             Mirai.HA.Connector.handle_info({:gun_ws, nil, nil, {:text, message}}, state)

    snapshot = Mirai.Runtime.snapshot(runtime)
    assert [automation] = snapshot.automations
    assert automation.status == "running"
    assert automation.duration_ms >= 25
    assert [event] = snapshot.events
    assert event.level == "success"
    assert event.message == "light.toggle → light.hall_light"
  end

  test "records a generic failure when a command is dropped before dispatch", %{runtime: runtime} do
    message = %{
      type: "call_service",
      domain: "light",
      service: "toggle",
      _runtime_source: TrackedAutomation,
      _runtime_target: "light.hall_light"
    }

    state = %{authenticated: false, runtime: runtime}

    assert {:noreply, ^state} = Mirai.HA.Connector.handle_cast({:send, message}, state)

    snapshot = Mirai.Runtime.snapshot(runtime)
    assert [automation] = snapshot.automations
    assert automation.status == "warning"
    assert [event] = snapshot.events
    assert event.message == "service dispatch failed"
    refute event.message =~ "light.hall_light"
  end
end
