defmodule Mirai.Automations.SharedActions do
  @moduledoc """
  Shared helper functions used across multiple automations.

  These are common actions like turning off all devices or entering night mode.
  """
  import Mirai.Automation.Helpers

  # Areas to turn off when doing "turn off everything"
  @all_light_areas ["dining_room", "hall", "kitchen", "living_room", "office"]

  @doc """
  Turns off all lights, switches, and media players in the house.
  """
  def turn_off_everything do
    # Turn off all lights in common areas
    call_service("light.turn_off", %{area_id: @all_light_areas})

    # Turn off switches (light chain, etc.)
    call_service("switch.turn_off", %{entity_id: "switch.zasuvka"})

    # Turn off TV in living room
    call_service("media_player.turn_off", %{area_id: "living_room"})
  end

  @doc """
  Enters night mode if within night hours (21:30 - 06:00).
  Always sets global state to "night".
  """
  def enter_night_mode do
    if night_time?() do
      set_global(:global_state, "night")
    end
  end

  @doc """
  Enters day mode - sets global state to "day".
  """
  def enter_day_mode do
    set_global(:global_state, "day")
  end

  @doc """
  Checks if current time is within night hours (21:30 - 06:00).
  """
  def night_time? do
    now = DateTime.utc_now() |> DateTime.shift_zone!("Europe/Prague")
    hour = now.hour
    minute = now.minute

    # Night time: 21:30 to 06:00
    cond do
      hour >= 21 and minute >= 30 -> true
      hour >= 22 -> true
      hour < 6 -> true
      true -> false
    end
  end

  @doc """
  Gets the current global state (day, night, or movie).
  Defaults to "day" if not set.
  """
  def current_mode do
    get_global(:global_state, "day")
  end

  @doc """
  Checks if the current mode is "day" or "movie" (active modes).
  """
  def active_mode? do
    mode = current_mode()
    mode == "day" or mode == "movie"
  end

  @doc """
  Checks if the current mode is "night".
  """
  def night_mode? do
    current_mode() == "night"
  end
end
