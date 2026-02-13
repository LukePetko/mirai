defmodule Mirai.Automation do
  @moduledoc """
  A behavior that simplifies writing Home Assistant automations.

  Instead of writing raw GenServer boilerplate, you can write:

      defmodule MyHome.KitchenButton do
        use Mirai.Automation

        def handle_event(%{entity_id: "sensor.kitchen_button"} = event, state) do
          if event.new_state.state == "single" do
            call_service("light.toggle", %{entity_id: "light.kitchen"})
          end
          {:ok, state}
        end

        def handle_event(_event, state), do: {:ok, state}
      end

  ## Callbacks

  - `handle_event/2` (required) - Called for every Home Assistant event
  - `initial_state/0` (optional) - Returns initial state, defaults to `%{}`
  - `handle_message/2` (optional) - Called for timer messages and custom messages

  ## Available Helpers

  When you `use Mirai.Automation`, these functions are automatically available:

  - `call_service/2` - Call a Home Assistant service
  - `schedule_timer/2` - Schedule a named timer
  - `cancel_timer/1` - Cancel a named timer

  ## Timers

  Timers are name-based for easy management:

      def handle_event(%{entity_id: "binary_sensor.motion"} = event, state) do
        if event.new_state.state == "on" do
          call_service("light.turn_on", %{entity_id: "light.hallway"})
          schedule_timer(:turn_off, :timer.minutes(5))
        end
        {:ok, state}
      end

      def handle_message(:turn_off, state) do
        call_service("light.turn_off", %{entity_id: "light.hallway"})
        {:ok, state}
      end

  Scheduling a timer with the same name cancels the previous one automatically.

  ## Schedules

  You can also declare time-based schedules using `@schedule`.

      @schedule daily: ~T[19:00:00], message: :evening
      @schedule sunset: [offset: -30], message: :pre_sunset
      @schedule every: :timer.minutes(15), message: :poll

  Scheduled messages are delivered to `handle_message/2`.
  """

  @doc "Called for every Home Assistant event"
  @callback handle_event(event :: Mirai.Event.t(), state :: term()) ::
              {:ok, new_state :: term()}

  @doc "Returns initial state for the automation. Defaults to %{}"
  @callback initial_state() :: term()

  @doc "Called when a timer fires or custom message is received"
  @callback handle_message(msg :: term(), state :: term()) :: {:ok, new_state :: term()}

  @optional_callbacks [initial_state: 0, handle_message: 2]

  defmacro __before_compile__(env) do
    schedules = Module.get_attribute(env.module, :schedule) || []

    quote location: :keep do
      @doc false
      def __schedules__, do: unquote(Macro.escape(schedules))
    end
  end

  defmacro __using__(_opts) do
    quote location: :keep do
      use GenServer
      require Logger
      @behaviour Mirai.Automation
      import Mirai.Automation.Helpers

      Module.register_attribute(__MODULE__, :schedule, accumulate: true)
      @before_compile Mirai.Automation

      # --- GenServer boilerplate ---

      def start_link(args \\ []) do
        GenServer.start_link(__MODULE__, args, name: __MODULE__)
      end

      def init(_args) do
        Phoenix.PubSub.subscribe(Mirai.PubSub, "ha:events")
        Phoenix.PubSub.subscribe(Mirai.PubSub, "mqtt:events")

        user_state =
          if function_exported?(__MODULE__, :initial_state, 0) do
            apply(__MODULE__, :initial_state, [])
          else
            %{}
          end

        Logger.info("[#{__MODULE__}] Started")
        {:ok, %{user_state: user_state, timers: %{}}}
      end

      # Handle HA events from PubSub
      def handle_info({:event, event}, state) do
        try do
          case __MODULE__.handle_event(event, state.user_state) do
            {:ok, new_user_state} ->
              {:noreply, %{state | user_state: new_user_state}}

            other ->
              Logger.warning(
                "[#{__MODULE__}] handle_event returned unexpected: #{inspect(other)}"
              )

              {:noreply, state}
          end
        rescue
          e ->
            Logger.error("[#{__MODULE__}] Error in handle_event: #{inspect(e)}")
            {:noreply, state}
        end
      end

      # Handle timer messages
      def handle_info({:timer, name}, state) do
        # Remove timer from tracking
        new_timers = Map.delete(state.timers, name)
        new_state = %{state | timers: new_timers}

        if function_exported?(__MODULE__, :handle_message, 2) do
          try do
            case apply(__MODULE__, :handle_message, [name, new_state.user_state]) do
              {:ok, new_user_state} ->
                {:noreply, %{new_state | user_state: new_user_state}}

              other ->
                Logger.warning(
                  "[#{__MODULE__}] handle_message returned unexpected: #{inspect(other)}"
                )

                {:noreply, new_state}
            end
          rescue
            e ->
              Logger.error("[#{__MODULE__}] Error in handle_message: #{inspect(e)}")
              {:noreply, new_state}
          end
        else
          Logger.warning(
            "[#{__MODULE__}] Timer #{inspect(name)} fired but no handle_message/2 defined"
          )

          {:noreply, new_state}
        end
      end

      # Handle scheduled messages
      def handle_info({:schedule, name}, state) do
        if function_exported?(__MODULE__, :handle_message, 2) do
          try do
            case apply(__MODULE__, :handle_message, [name, state.user_state]) do
              {:ok, new_user_state} ->
                {:noreply, %{state | user_state: new_user_state}}

              other ->
                Logger.warning(
                  "[#{__MODULE__}] handle_message returned unexpected: #{inspect(other)}"
                )

                {:noreply, state}
            end
          rescue
            e ->
              Logger.error("[#{__MODULE__}] Error in handle_message: #{inspect(e)}")
              {:noreply, state}
          end
        else
          Logger.warning(
            "[#{__MODULE__}] Scheduled message #{inspect(name)} received but no handle_message/2 defined"
          )

          {:noreply, state}
        end
      end

      # Catch-all for other messages
      def handle_info(msg, state) do
        Logger.debug("[#{__MODULE__}] Received unknown message: #{inspect(msg)}")
        {:noreply, state}
      end

      # Allow accessing internal state (for debugging)
      def handle_call(:get_state, _from, state) do
        {:reply, state, state}
      end

      # --- Timer management (called from helpers via GenServer.cast) ---

      def handle_cast({:schedule_timer, name, delay}, state) do
        # Cancel existing timer with same name if present
        new_timers =
          case Map.get(state.timers, name) do
            nil ->
              state.timers

            old_ref ->
              Process.cancel_timer(old_ref)
              state.timers
          end

        # Schedule new timer
        ref = Process.send_after(self(), {:timer, name}, delay)
        {:noreply, %{state | timers: Map.put(new_timers, name, ref)}}
      end

      def handle_cast({:cancel_timer, name}, state) do
        new_timers =
          case Map.get(state.timers, name) do
            nil ->
              state.timers

            ref ->
              Process.cancel_timer(ref)
              Map.delete(state.timers, name)
          end

        {:noreply, %{state | timers: new_timers}}
      end

      defoverridable init: 1
    end
  end
end
