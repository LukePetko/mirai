defmodule Mirai.Automations.KitchenQuickAction do
  @moduledoc """
  Kitchen Quick Action Button automation.

  Button actions:
  - "on": Toggle kitchen lights
  - "brightness_move_up": Toggle dining room lamp
  """
  use Mirai.Automation

  @kitchen_lights ["light.kitchen_1", "light.kitchen_2"]

  # "on" action → Toggle kitchen lights
  def handle_event(%{entity_id: "sensor.kitchen_qab_action", new_state: %{state: "on"}}, state) do
    case get_state("light.kitchen") do
      {:ok, %{state: "on"}} ->
        call_service("light.turn_off", %{entity_id: "light.kitchen"})

      _ ->
        call_service("light.turn_on", %{entity_id: @kitchen_lights, brightness_pct: 100})
    end

    {:ok, state}
  end

  # "brightness_move_up" action → Toggle dining
  def handle_event(
        %{entity_id: "sensor.kitchen_qab_action", new_state: %{state: "brightness_move_up"}},
        state
      ) do
    call_service("light.toggle", %{entity_id: "light.dining_room_lamp"})
    {:ok, state}
  end

  def handle_event(_event, state), do: {:ok, state}
end
