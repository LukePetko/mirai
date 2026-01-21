defmodule Mirai.GlobalState do
  @moduledoc """
  Persistent key-value store for global state shared across automations.

  Uses DETS (Disk-based Erlang Term Storage) for automatic persistence.
  State survives application restarts.

  ## Usage in automations

      # Set a value
      set_global(:night_mode, true)
      set_global(:house_mode, :away)
      set_global(:last_motion, DateTime.utc_now())

      # Get a value (with optional default)
      get_global(:night_mode)           # => true or nil
      get_global(:night_mode, false)    # => true or false (default)

      # Delete a value
      delete_global(:night_mode)

  ## Example: Day/Night mode

      defmodule MyHome.DayNightMode do
        use Mirai.Automation

        # Sun sensor triggers this
        def handle_event(%{entity_id: "sun.sun"} = event, state) do
          case event.new_state.state do
            "below_horizon" -> set_global(:night_mode, true)
            "above_horizon" -> set_global(:night_mode, false)
          end
          {:ok, state}
        end

        def handle_event(_event, state), do: {:ok, state}
      end

      defmodule MyHome.LightController do
        use Mirai.Automation

        def handle_event(%{entity_id: "binary_sensor.motion"}, state) do
          brightness = if get_global(:night_mode, false), do: 50, else: 255
          call_service("light.turn_on", %{entity_id: "light.hallway", brightness: brightness})
          {:ok, state}
        end

        def handle_event(_event, state), do: {:ok, state}
      end

  ## Notes

  - Values can be any Erlang term (atoms, maps, lists, tuples, etc.)
  - Writes are synchronous and immediately persisted
  - Reads are fast (direct DETS lookup)
  - DETS file is stored in `priv/data/global_state.dets`
  """

  use GenServer
  require Logger

  @table :mirai_global_state

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets a value from global state.

  Returns the value or `default` if not found (default is `nil`).

  ## Examples

      get(:night_mode)          # => true, false, or nil
      get(:night_mode, false)   # => true or false
      get(:counter, 0)          # => integer or 0
  """
  def get(key, default \\ nil) do
    case :dets.lookup(@table, key) do
      [{^key, value}] -> value
      [] -> default
    end
  end

  @doc """
  Sets a value in global state.

  The value is immediately persisted to disk.

  ## Examples

      set(:night_mode, true)
      set(:house_mode, :away)
      set(:last_motion, %{room: "kitchen", at: DateTime.utc_now()})
  """
  def set(key, value) do
    :dets.insert(@table, {key, value})
    :ok
  end

  @doc """
  Deletes a key from global state.

  ## Example

      delete(:temporary_flag)
  """
  def delete(key) do
    :dets.delete(@table, key)
    :ok
  end

  @doc """
  Returns all key-value pairs as a map.

  ## Example

      all()  # => %{night_mode: true, house_mode: :home}
  """
  def all do
    :dets.foldl(fn {key, value}, acc -> Map.put(acc, key, value) end, %{}, @table)
  end

  @doc """
  Returns all keys.

  ## Example

      keys()  # => [:night_mode, :house_mode]
  """
  def keys do
    :dets.foldl(fn {key, _value}, acc -> [key | acc] end, [], @table)
  end

  @doc """
  Clears all global state. Use with caution!
  """
  def clear do
    :dets.delete_all_objects(@table)
    :ok
  end

  # --- GenServer callbacks ---

  def init(_opts) do
    # Ensure data directory exists
    data_dir = Path.join(:code.priv_dir(:mirai), "data")
    File.mkdir_p!(data_dir)

    # Open DETS table (creates file if doesn't exist)
    dets_file = Path.join(data_dir, "global_state.dets") |> String.to_charlist()

    case :dets.open_file(@table, file: dets_file, type: :set) do
      {:ok, @table} ->
        Logger.info("[GlobalState] Opened persistent storage at #{dets_file}")
        {:ok, %{}}

      {:error, reason} ->
        Logger.error("[GlobalState] Failed to open DETS: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  def terminate(_reason, _state) do
    :dets.close(@table)
    :ok
  end
end
