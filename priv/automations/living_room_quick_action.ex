defmodule Mirai.Automations.LivingRoomQuickAction do
  @moduledoc """
  Living Room Quick Action Button automation.

  Button actions:
  - "on": Toggle living room lights (behavior depends on global state)
    - Day/Movie mode: Toggle ceiling + light chain
    - Night mode: Toggle accent lights at low brightness
  - "brightness_move_up": Enter night mode or wake up
    - Day/Movie mode: Turn off everything + enter night mode
    - Night mode: Enter day mode
  """
  use Mirai.Automation
  alias Mirai.Automations.SharedActions

  @accent_lights [
    "light.accent_1",
    "light.accent_2",
    "light.accent_3",
    "light.accent_4"
  ]

  # --- "on" action ---
  def handle_event(
        %{entity_id: "sensor.living_room_qab_action", new_state: %{state: "on"}},
        state
      ) do
    if SharedActions.active_mode?() do
      handle_on_active_mode()
    else
      handle_on_night_mode()
    end

    {:ok, state}
  end

  # --- "brightness_move_up" action ---
  def handle_event(
        %{entity_id: "sensor.living_room_qab_action", new_state: %{state: "brightness_move_up"}},
        state
      ) do
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

  def handle_event(_event, state), do: {:ok, state}

  # --- Private helpers ---

  defp handle_on_active_mode do
    case get_state("light.living_room") do
      {:ok, %{state: "on"}} ->
        # Living room is on -> turn off
        call_service("light.turn_off", %{area_id: "living_room"})
        call_service("switch.turn_off", %{entity_id: "switch.zasuvka"})

      _ ->
        # Living room is off -> turn on ceiling + light chain
        call_service("light.turn_on", %{entity_id: "light.ceiling", brightness_pct: 100})
        call_service("switch.turn_on", %{entity_id: "switch.zasuvka"})
    end
  end

  defp handle_on_night_mode do
    case get_state("light.living_room") do
      {:ok, %{state: "on"}} ->
        # Living room is on -> turn off
        call_service("light.turn_off", %{area_id: "living_room"})

      _ ->
        # Living room is off -> turn on accent lights at low brightness
        call_service("light.turn_on", %{entity_id: @accent_lights, brightness_pct: 10})
    end
  end
end
