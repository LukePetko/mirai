defmodule Mirai.Automations.BedroomNightstandButton do
  @moduledoc """
  Bedroom Nightstand Quick Action Button automation.

  Handles the nightstand button (sensor.bedroom_quick_action_button_action).
  This is a 2-button device with short and long press actions.

  Button actions:
  - "1_short_release": Toggle bedroom wall lights at 30% brightness
  - "2_short_release": Toggle bedroom top light
  - "1_long_press" / "2_long_press": Night mode toggle (same as desk double-press)
  """
  use Mirai.Automation
  alias Mirai.Automations.SharedActions

  @bedroom_wall_lights ["light.bedroom_1_4", "light.bedroom_2_2"]
  @bedroom_top_light "light.lightbulb"

  # Button 1 short press -> Toggle bedroom wall lights
  def handle_event(
        %{
          entity_id: "sensor.bedroom_quick_action_button_action",
          new_state: %{state: "1_short_release"}
        },
        state
      ) do
    call_service("light.toggle", %{entity_id: @bedroom_wall_lights, brightness_pct: 30})
    {:ok, state}
  end

  # Button 2 short press -> Toggle bedroom top light
  def handle_event(
        %{
          entity_id: "sensor.bedroom_quick_action_button_action",
          new_state: %{state: "2_short_release"}
        },
        state
      ) do
    call_service("light.toggle", %{entity_id: @bedroom_top_light, brightness_pct: 100})
    {:ok, state}
  end

  # Button 1 long press -> Night mode toggle
  def handle_event(
        %{
          entity_id: "sensor.bedroom_quick_action_button_action",
          new_state: %{state: "1_long_press"}
        },
        state
      ) do
    toggle_night_mode()
    {:ok, state}
  end

  # Button 2 long press -> Night mode toggle
  def handle_event(
        %{
          entity_id: "sensor.bedroom_quick_action_button_action",
          new_state: %{state: "2_long_press"}
        },
        state
      ) do
    toggle_night_mode()
    {:ok, state}
  end

  def handle_event(_event, state), do: {:ok, state}

  # --- Private helpers ---

  defp toggle_night_mode do
    if SharedActions.active_mode?() do
      SharedActions.turn_off_everything()
      SharedActions.enter_night_mode()
    else
      SharedActions.enter_day_mode()
    end
  end
end
