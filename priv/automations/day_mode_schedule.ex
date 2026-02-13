defmodule Mirai.Automations.DayModeSchedule do
  use Mirai.Automation

  @schedule daily: ~T[07:00:00], message: :enter_day_mode

  def handle_message(:enter_day_mode, state) do
    Mirai.Automations.SharedActions.enter_day_mode()
    {:ok, state}
  end

  def handle_event(_event, state), do: {:ok, state}
end
