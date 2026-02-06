defmodule Mirai.Automations.HallQuickAction do
  @moduledoc """
  Hall Quick Action Button automation.

  Button actions:
  - "on": Toggle hall lights at full brightness
  - "brightness_move_up": Turn off everything in the house
  """
  use Mirai.Automation
  alias Mirai.Automations.SharedActions

  # "on" action -> Toggle hall lights
  def handle_event(%{entity_id: "sensor.hall_qab_action", new_state: %{state: "on"}}, state) do
    call_service("light.toggle", %{area_id: "hall", brightness_pct: 100})
    {:ok, state}
  end

  # "brightness_move_up" action -> Turn off everything
  def handle_event(
        %{entity_id: "sensor.hall_qab_action", new_state: %{state: "brightness_move_up"}},
        state
      ) do
    SharedActions.turn_off_everything()
    {:ok, state}
  end

  def handle_event(_event, state), do: {:ok, state}
end
