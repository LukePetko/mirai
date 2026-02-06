defmodule Mirai.Automations.OfficeQuickAction do
  @moduledoc """
  Office Quick Action Button automation.

  Button actions:
  - "on": Toggle office lights (all desk lamps)
  - "brightness_move_up": Toggle top office lights
  """
  use Mirai.Automation

  @office_desk_lights ["light.luky_top", "light.niki_top", "light.table_lamp_color"]
  @office_top_lights ["light.office_top_1", "light.office_top_2_6", "light.office_top_3_5"]

  # "on" action -> Toggle office lights
  def handle_event(%{entity_id: "sensor.office_qab_action", new_state: %{state: "on"}}, state) do
    case get_state("light.office") do
      {:ok, %{state: "on"}} ->
        call_service("light.turn_off", %{entity_id: "light.office"})

      _ ->
        call_service("light.turn_on", %{entity_id: @office_desk_lights, brightness_pct: 100})
    end

    {:ok, state}
  end

  # "brightness_move_up" action -> Toggle top office lights
  def handle_event(
        %{entity_id: "sensor.office_qab_action", new_state: %{state: "brightness_move_up"}},
        state
      ) do
    call_service("light.toggle", %{entity_id: @office_top_lights, brightness_pct: 100})
    {:ok, state}
  end

  def handle_event(_event, state), do: {:ok, state}
end
