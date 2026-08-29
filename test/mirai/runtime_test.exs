defmodule Mirai.RuntimeTest do
  use ExUnit.Case, async: false

  defmodule HallAutomation do
  end

  setup do
    runtime =
      start_supervised!(
        {Mirai.Runtime, name: :runtime_test, automations: [HallAutomation], max_events: 2}
      )

    Process.register(self(), HallAutomation)

    on_exit(fn ->
      if Process.whereis(HallAutomation) == self(), do: Process.unregister(HallAutomation)
    end)

    %{runtime: runtime}
  end

  test "reports loaded automations and bounded recent action history", %{runtime: runtime} do
    Mirai.Runtime.record_action(HallAutomation, "light.toggle", "light.hall_light", 84, runtime)
    Mirai.Runtime.record_action(HallAutomation, "light.turn_off", "light.hall_light", 91, runtime)
    Mirai.Runtime.record_action(HallAutomation, "light.turn_on", "light.hall_light", 76, runtime)

    snapshot = Mirai.Runtime.snapshot(runtime)

    assert snapshot.source == "runtime"
    assert snapshot.metrics.loaded_automations == 1
    assert snapshot.metrics.expected_automations == 1
    assert snapshot.runtime.status == "online"

    assert [automation] = snapshot.automations
    assert automation.id == "Mirai.RuntimeTest.HallAutomation"
    assert automation.name == "HallAutomation"
    assert automation.status == "running"
    assert automation.target == "light.hall_light"
    assert automation.last_run_at
    assert automation.duration_ms == 76

    assert length(snapshot.events) == 2
    assert hd(snapshot.events).message == "light.turn_on → light.hall_light"
  end

  test "records callback failures without exposing exception internals", %{runtime: runtime} do
    Mirai.Runtime.record_error(HallAutomation, "handle_event", runtime)

    snapshot = Mirai.Runtime.snapshot(runtime)

    assert [automation] = snapshot.automations
    assert automation.status == "warning"

    assert [event] = snapshot.events
    assert event.level == "error"
    assert event.source == "HallAutomation"
    assert event.message == "handle_event failed"
  end

  test "ignores unconfigured sources", %{runtime: runtime} do
    Mirai.Runtime.record_action(
      __MODULE__,
      "light.toggle",
      String.duplicate("x", 1_000),
      10,
      runtime
    )

    Mirai.Runtime.record_error(__MODULE__, "unknown callback", runtime)

    snapshot = Mirai.Runtime.snapshot(runtime)

    assert snapshot.metrics.expected_automations == 1
    assert snapshot.events == []
  end
end
