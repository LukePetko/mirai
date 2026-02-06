defmodule Mirai.Automations.BedroomQuickAction do
  @moduledoc """
  Bedroom Quick Action Button automation.

  Handles the standard bedroom button (sensor.bedroom_qab_action).

  Button actions:
  - "on": Toggle bedroom wall lights at 30% brightness
  - "brightness_move_up": Toggle bedroom top light at full brightness
  """
  use Mirai.Automation

  @bedroom_wall_lights ["light.bedroom_1_4", "light.bedroom_2_2"]
  @bedroom_top_light "light.lightbulb"

  # "on" action -> Toggle bedroom wall lights
  def handle_event(%{entity_id: "sensor.bedroom_qab_action", new_state: %{state: "on"}}, state) do
    call_service("light.toggle", %{entity_id: @bedroom_wall_lights, brightness_pct: 30})
    {:ok, state}
  end

  # "brightness_move_up" action -> Toggle bedroom top light
  def handle_event(
        %{entity_id: "sensor.bedroom_qab_action", new_state: %{state: "brightness_move_up"}},
        state
      ) do
    call_service("light.toggle", %{entity_id: @bedroom_top_light, brightness_pct: 100})
    {:ok, state}
  end

  def handle_event(_event, state), do: {:ok, state}
end
