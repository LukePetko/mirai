defmodule Mirai.Automation.Helpers do
  @moduledoc """
  Helper functions automatically available in automations.

  These are imported when you `use Mirai.Automation`, so you can call them
  directly without any prefix.

  ## Example

      defmodule MyAutomation do
        use Mirai.Automation

        def handle_event(event, state) do
          # These are all available without prefix:
          call_service("light.turn_on", %{entity_id: "light.kitchen"})
          schedule_timer(:turn_off, 5000)
          cancel_timer(:turn_off)
          {:ok, state}
        end
      end
  """

  @doc """
  Calls a Home Assistant service.

  ## Examples

      # Turn on a light
      call_service("light.turn_on", %{entity_id: "light.kitchen"})

      # Turn on with brightness
      call_service("light.turn_on", %{entity_id: "light.kitchen", brightness: 255})

      # Toggle a light
      call_service("light.toggle", %{entity_id: "light.living_room"})

      # Turn off multiple lights
      call_service("light.turn_off", %{entity_id: ["light.kitchen", "light.hallway"]})

      # Set climate
      call_service("climate.set_temperature", %{entity_id: "climate.main", temperature: 22})
  """
  def call_service(service_string, data \\ %{}) do
    case String.split(service_string, ".", parts: 2) do
      [domain, service] ->
        Mirai.HA.Helpers.call_service(domain, service, data)

      _ ->
        require Logger

        Logger.error(
          "Invalid service format: #{inspect(service_string)}. Expected \"domain.service\""
        )

        :error
    end
  end

  @doc """
  Schedules a named timer.

  After `delay` milliseconds, `handle_message/2` will be called with `name`.

  If a timer with the same name already exists, it is cancelled and replaced.

  ## Examples

      # Turn off light after 5 minutes
      schedule_timer(:turn_off, :timer.minutes(5))

      # Send reminder after 30 seconds
      schedule_timer(:reminder, :timer.seconds(30))

      # Using raw milliseconds
      schedule_timer(:quick, 500)

  ## Notes

  - `:timer.minutes(5)` returns 300000 (milliseconds)
  - `:timer.seconds(30)` returns 30000 (milliseconds)
  - `:timer.hours(1)` returns 3600000 (milliseconds)
  """
  def schedule_timer(name, delay) do
    GenServer.cast(self(), {:schedule_timer, name, delay})
  end

  @doc """
  Cancels a named timer.

  If no timer with that name exists, this is a no-op.

  ## Example

      # Motion detected again, reset the turn-off timer
      def handle_event(%{entity_id: "binary_sensor.motion"} = event, state) do
        if event.new_state.state == "on" do
          cancel_timer(:turn_off)  # Cancel pending turn-off
          schedule_timer(:turn_off, :timer.minutes(5))  # Start new timer
        end
        {:ok, state}
      end
  """
  def cancel_timer(name) do
    GenServer.cast(self(), {:cancel_timer, name})
  end

  @doc """
  Gets the current state of a Home Assistant entity.

  Returns `{:ok, state_map}` or `{:error, :not_found}`.

  The state map contains:
  - `state` - The entity's state string (e.g., "on", "off", "22.5")
  - `attributes` - Map of entity attributes (e.g., brightness, friendly_name)
  - `last_changed` - ISO8601 timestamp of last state change
  - `last_updated` - ISO8601 timestamp of last update

  ## Examples

      # Check if a light is on
      case get_state("light.kitchen") do
        {:ok, %{state: "on"}} -> Logger.info("Kitchen light is on")
        {:ok, %{state: "off"}} -> Logger.info("Kitchen light is off")
        {:error, :not_found} -> Logger.warn("Entity not found")
      end

      # Get temperature
      {:ok, %{state: temp}} = get_state("sensor.temperature")
      temp_float = String.to_float(temp)

      # Check brightness attribute
      {:ok, %{attributes: %{"brightness" => brightness}}} = get_state("light.bedroom")
  """
  def get_state(entity_id) do
    Mirai.HA.StateCache.get_state(entity_id)
  end

  @doc """
  Gets the current state of a Home Assistant entity, raises if not found.

  Same as `get_state/1` but returns the state map directly or raises.

  ## Examples

      # When you're sure the entity exists
      %{state: state} = get_state!("light.kitchen")

      # Pattern match directly
      %{state: "on"} = get_state!("light.kitchen")  # raises MatchError if off
  """
  def get_state!(entity_id) do
    Mirai.HA.StateCache.get_state!(entity_id)
  end

  # --- Global State Helpers ---

  @doc """
  Gets a value from persistent global state.

  Global state is shared across all automations and persists across restarts.

  ## Examples

      # Get with nil default
      get_global(:night_mode)           # => true, false, or nil

      # Get with explicit default
      get_global(:night_mode, false)    # => true or false
      get_global(:counter, 0)           # => stored value or 0

      # Complex values work too
      get_global(:last_motion)          # => %{room: "kitchen", at: ~U[...]}
  """
  def get_global(key, default \\ nil) do
    Mirai.GlobalState.get(key, default)
  end

  @doc """
  Sets a value in persistent global state.

  The value is immediately persisted to disk and survives restarts.

  ## Examples

      # Simple values
      set_global(:night_mode, true)
      set_global(:house_mode, :away)

      # Complex values
      set_global(:last_motion, %{room: "kitchen", at: DateTime.utc_now()})

  ## Use cases

      # Track day/night mode
      def handle_event(%{entity_id: "sun.sun"} = event, state) do
        case event.new_state.state do
          "below_horizon" -> set_global(:night_mode, true)
          "above_horizon" -> set_global(:night_mode, false)
        end
        {:ok, state}
      end

      # Then in another automation
      def handle_event(event, state) do
        brightness = if get_global(:night_mode), do: 50, else: 255
        call_service("light.turn_on", %{entity_id: "light.hall", brightness: brightness})
        {:ok, state}
      end
  """
  def set_global(key, value) do
    Mirai.GlobalState.set(key, value)
  end

  @doc """
  Deletes a key from persistent global state.

  ## Example

      delete_global(:temporary_flag)
  """
  def delete_global(key) do
    Mirai.GlobalState.delete(key)
  end
end
