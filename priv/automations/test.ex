defmodule Mirai.Automations.Test do
  use GenServer
  require Logger
  import Mirai.Entities
  import Mirai.HA.Helpers

  @moduledoc """
  Turn on lights when motion is detected in any room
  """

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    Logger.info("#{__MODULE__} started")
    Phoenix.PubSub.subscribe(Mirai.PubSub, "ha:events")
    {:ok, %{}}
  end

  def handle_info({:event, event}, state) do
    if matches?(event) do
      Task.start(fn -> execute(event) end)
      Logger.info("[MotionLight] Motion detected in #{event.entity_id}! Turning on light")
    end

    {:noreply, state}
  end

  defp matches?(event) do
    # event.entity_id == sensor_office_qab_action() and
    #   event.new_state.state == "brightness_move_up"
    event.entity_id == "test"
  end

  @spec turn_off_light(Mirai.Entities.entity_id()) :: :ok
  def turn_off_light(entity_id) do
    Logger.info("[MotionLight] Turning off #{entity_id}")
  end

  defp execute(_event) do
    # call_sevice("light", "toggle", %{entity_id: light_table_lamp_color()})
    call_sevice("light", "toggle", %{entity_id: light_bodovka_7()})

    # # Extract room name from sensor entity_id
    # # e.g., "binary_sensor.motion_kitchen" -> "kitchen"
    # room = 
    #   event["entity_id"]
    #   |> String.replace("binary_sensor.motion_", "")
    # 
    # light_entity = "light.#{room}"
    # 
    # Logger.info("[MotionLight] Motion detected in #{room}! Turning on #{light_entity}")
    # 
    # Mirai.HA.Connector.send_command(%{
    #   id: :erlang.unique_integer([:positive]),
    #   type: "call_service",
    #   domain: "light",
    #   service: "turn_on",
    #   service_data: %{
    #     entity_id: light_entity,
    #     brightness: 255
    #   }
    # })
  end
end
