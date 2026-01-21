defmodule Mirai.Automations.KitchenButton do
  use Mirai.Automation

  def handle_event(%{entity_id: "sensor.kitchen_button", new_state: %{state: "single"}}, state) do
    call_service("light.toggle", %{entity_id: "light.kitchen"})
    {:ok, state}
  end

  def handle_event(_event, state), do: {:ok, state}
end
