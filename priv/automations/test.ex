defmodule Mirai.Automations.Test do
  use Mirai.Automation

  @schedule daily: ~T[13:05:00], message: :enter_day_mode

  def handle_message(:enter_day_mode, state) do
    call_service("light.turn_on", %{entity_id: "light.ceiling", brightness_pct: 100})
    call_service("switch.turn_on", %{entity_id: "switch.zasuvka"})
    {:ok, state}
  end

  def handle_event(_event, state), do: {:ok, state}
end
