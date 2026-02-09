defmodule Mirai.Automations.PomodoroSession do
  use Mirai.Automation

  def handle_event(%{source: :mqtt, entity_id: "pomodoro/timer/session"} = event, state) do
    Logger.info("Event: #{inspect(event)}")

    send_notification(event.attributes)
    toggle_table_lamp(state)
    {:ok, state}
  end

  def handle_event(_event, state), do: {:ok, state}

  def toggle_table_lamp(state) do
    call_service("light.toggle", %{entity_id: "light.table_lamp_color"})
    Process.sleep(1000)
    call_service("light.toggle", %{entity_id: "light.table_lamp_color"})
    {:ok, state}
  end

  def send_notification(payload) do
    if payload["event_type"] == "start" do
      :ok
    else
      message =
        case payload["timer_type"] do
          "work" ->
            session = div(payload["session_number"], 2) + 1
            "Work session #{session} ended. Take some rest."

          "short_break" ->
            "Pause ended. Go back to work!"

          "long_break" ->
            "All sessions ended, please start new timer once you're ready"

          _ ->
            nil
        end

      if message do
        Logger.info("Pomodoro: #{message}")

        call_service("notify.mobile_app_lukes_iphone_16_pro", %{
          message: message,
          title: "Pomodoro"
        })
      end

      :ok
    end
  end
end
