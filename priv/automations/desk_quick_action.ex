defmodule Mirai.Automations.DeskQuickAction do
  @moduledoc """
  Desk Quick Action Button automation.

  Handles the desk button (sensor.desk_qab_action) which uses Zigbee button actions.

  Button actions:
  - "single": Toggle bedroom wall lights at 30% brightness
  - "double": Turn off everything + enter night mode (or enter day mode if in night)
  - "hold": Toggle bedroom top light
  """
  use Mirai.Automation
  alias Mirai.Automations.SharedActions

  @bedroom_wall_lights ["light.bedroom_1_4", "light.bedroom_2_2"]
  @bedroom_top_light "light.lightbulb"

  # "single" action -> Toggle bedroom wall lights
  def handle_event(%{entity_id: "sensor.desk_qab_action", new_state: %{state: "single"}}, state) do
    call_service("light.toggle", %{entity_id: @bedroom_wall_lights, brightness_pct: 30})
    {:ok, state}
  end

  # "double" action -> Night mode toggle
  def handle_event(%{entity_id: "sensor.desk_qab_action", new_state: %{state: "double"}}, state) do
    if SharedActions.active_mode?() do
      # Day/movie mode: turn off everything and enter night mode
      SharedActions.turn_off_everything()
      SharedActions.enter_night_mode()
    else
      # Night mode: enter day mode
      SharedActions.enter_day_mode()
    end

    {:ok, state}
  end

  # "hold" action -> Toggle bedroom top light
  def handle_event(%{entity_id: "sensor.desk_qab_action", new_state: %{state: "hold"}}, state) do
    call_service("light.toggle", %{entity_id: @bedroom_top_light, brightness_pct: 100})
    {:ok, state}
  end

  def handle_event(_event, state), do: {:ok, state}
end
