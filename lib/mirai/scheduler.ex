defmodule Mirai.Scheduler do
  @moduledoc """
  Time-based scheduling for automations.

  Automations can declare schedules using the `@schedule` module attribute.
  When a schedule fires, the automation receives `{:schedule, message}` which is
  dispatched to the existing `handle_message/2` callback.

  Supported schedules:

  - `@schedule daily: ~T[HH:MM:SS], message: :msg`
  - `@schedule sunrise: [offset: minutes], message: :msg`
  - `@schedule sunset: [offset: minutes], message: :msg`
  - `@schedule every: milliseconds, message: :msg`

  Sunrise and sunset calculations are local (no Home Assistant dependency).
  Configure location via environment variables:

  - `MIRAI_LATITUDE`
  - `MIRAI_LONGITUDE`
  - `MIRAI_TIMEZONE` (defaults to "Europe/Prague")
  """

  use GenServer
  require Logger

  @type schedule_kind :: :daily | :sunrise | :sunset | :every

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    timezone = normalize_timezone(Keyword.get(opts, :timezone, "Europe/Prague"))
    latitude = Keyword.get(opts, :latitude)
    longitude = Keyword.get(opts, :longitude)
    location = normalize_location(latitude, longitude)
    automations = Keyword.get(opts, :automations, [])

    schedules = load_schedules(automations)

    state = %{
      timezone: timezone,
      location: location,
      schedules: %{},
      timers: %{}
    }

    state =
      Enum.reduce(schedules, state, fn schedule, acc ->
        acc
        |> put_schedule(schedule)
        |> schedule_next(schedule.id)
      end)

    Logger.info("[Mirai.Scheduler] Loaded #{map_size(state.schedules)} schedule(s)")

    {:ok, state}
  end

  @impl true
  def handle_info({:fire, id}, state) do
    state = cancel_timer(state, id)

    case Map.fetch(state.schedules, id) do
      :error ->
        {:noreply, state}

      {:ok, schedule} ->
        deliver(schedule)
        {:noreply, schedule_next(state, id)}
    end
  end

  def handle_info(msg, state) do
    Logger.debug("[Mirai.Scheduler] Received unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  # --- Internal ---

  defp normalize_timezone(tz) when is_binary(tz) do
    case DateTime.shift_zone(DateTime.utc_now(), tz) do
      {:ok, _} ->
        tz

      {:error, reason} ->
        Logger.warning(
          "[Mirai.Scheduler] Invalid MIRAI_TIMEZONE #{inspect(tz)} (#{inspect(reason)}), falling back to Etc/UTC"
        )

        "Etc/UTC"
    end
  end

  defp normalize_timezone(_), do: "Etc/UTC"

  defp normalize_location(lat, lng) when is_number(lat) and is_number(lng) do
    {lng, lat}
  end

  defp normalize_location(_lat, _lng), do: nil

  defp load_schedules(modules) do
    modules
    |> Enum.flat_map(fn mod ->
      if function_exported?(mod, :__schedules__, 0) do
        try do
          mod.__schedules__()
          |> Enum.with_index()
          |> Enum.flat_map(fn {decl, idx} ->
            case parse_schedule(mod, decl, idx) do
              {:ok, schedule} ->
                [schedule]

              {:error, reason} ->
                Logger.warning(
                  "[Mirai.Scheduler] Ignoring invalid schedule in #{inspect(mod)}: #{inspect(decl)} (#{inspect(reason)})"
                )

                []
            end
          end)
        rescue
          e ->
            Logger.error(
              "[Mirai.Scheduler] Failed to load schedules from #{inspect(mod)}: #{inspect(e)}"
            )

            []
        end
      else
        []
      end
    end)
  end

  defp parse_schedule(mod, decl, idx) when is_list(decl) do
    with {:ok, message} <- fetch_message(decl) do
      cond do
        Keyword.has_key?(decl, :daily) ->
          time = Keyword.get(decl, :daily)
          id = {mod, message, idx}

          if match?(%Time{}, time) do
            {:ok, %{id: id, module: mod, kind: :daily, message: message, time: time}}
          else
            {:error, :invalid_time}
          end

        Keyword.has_key?(decl, :sunrise) ->
          opts = Keyword.get(decl, :sunrise, [])
          id = {mod, message, idx}

          {:ok,
           %{
             id: id,
             module: mod,
             kind: :sunrise,
             message: message,
             offset_min: offset_minutes(opts)
           }}

        Keyword.has_key?(decl, :sunset) ->
          opts = Keyword.get(decl, :sunset, [])
          id = {mod, message, idx}

          {:ok,
           %{
             id: id,
             module: mod,
             kind: :sunset,
             message: message,
             offset_min: offset_minutes(opts)
           }}

        Keyword.has_key?(decl, :every) ->
          every_ms = Keyword.get(decl, :every)
          id = {mod, message, idx}

          if is_integer(every_ms) and every_ms > 0 do
            {:ok, %{id: id, module: mod, kind: :every, message: message, every_ms: every_ms}}
          else
            {:error, :invalid_every}
          end

        true ->
          {:error, :unknown_schedule}
      end
    end
  end

  defp parse_schedule(_mod, _decl, _idx), do: {:error, :invalid_declaration}

  defp fetch_message(decl) do
    case Keyword.fetch(decl, :message) do
      {:ok, msg} -> {:ok, msg}
      :error -> {:error, :missing_message}
    end
  end

  defp offset_minutes(opts) when is_list(opts) do
    case Keyword.get(opts, :offset, 0) do
      offset when is_integer(offset) -> offset
      _ -> 0
    end
  end

  defp put_schedule(state, schedule) do
    %{state | schedules: Map.put(state.schedules, schedule.id, schedule)}
  end

  defp schedule_next(state, id) do
    case Map.fetch(state.schedules, id) do
      :error ->
        state

      {:ok, schedule} ->
        case next_delay(schedule, state) do
          {:ok, delay_ms, next_at} ->
            ref = Process.send_after(self(), {:fire, id}, delay_ms)

            log_next(schedule, delay_ms, next_at, state.timezone)
            %{state | timers: Map.put(state.timers, id, ref)}

          {:error, reason} ->
            Logger.warning(
              "[Mirai.Scheduler] Could not schedule #{inspect(schedule.module)} #{inspect(schedule.message)} (#{schedule.kind}): #{inspect(reason)}"
            )

            state
        end
    end
  end

  defp cancel_timer(state, id) do
    case Map.get(state.timers, id) do
      nil ->
        state

      ref ->
        _ = Process.cancel_timer(ref)
        %{state | timers: Map.delete(state.timers, id)}
    end
  end

  defp next_delay(%{kind: :every, every_ms: ms}, _state) do
    {:ok, ms, nil}
  end

  defp next_delay(%{kind: :daily, time: time}, state) do
    now = local_now(state.timezone)
    next_dt = next_daily_datetime(now, time, state.timezone)
    {:ok, max(DateTime.diff(next_dt, now, :millisecond), 0), next_dt}
  end

  defp next_delay(%{kind: kind, offset_min: offset_min}, state)
       when kind in [:sunrise, :sunset] do
    now = local_now(state.timezone)

    case state.location do
      nil ->
        {:error, :missing_location}

      location ->
        with {:ok, next_dt} <- next_solar_event(kind, location, now, offset_min, state.timezone) do
          {:ok, max(DateTime.diff(next_dt, now, :millisecond), 0), next_dt}
        end
    end
  end

  defp local_now(timezone) do
    utc = DateTime.utc_now()

    case DateTime.shift_zone(utc, timezone) do
      {:ok, local} -> local
      {:error, _} -> utc
    end
  end

  defp next_daily_datetime(now, time, timezone) do
    date = DateTime.to_date(now)
    candidate = local_datetime_for(date, time, timezone)

    if DateTime.compare(candidate, now) == :gt do
      candidate
    else
      local_datetime_for(Date.add(date, 1), time, timezone)
    end
  end

  defp local_datetime_for(date, time, timezone) do
    naive = NaiveDateTime.new!(date, time)

    case DateTime.from_naive(naive, timezone) do
      {:ok, dt} ->
        dt

      {:ambiguous, _dt1, dt2} ->
        dt2

      {:gap, _dt1, dt2} ->
        dt2

      {:error, _} ->
        DateTime.from_naive!(naive, "Etc/UTC")
    end
  end

  defp next_solar_event(kind, location, now, offset_min, timezone) do
    start_date = DateTime.to_date(now)

    0..1
    |> Enum.reduce_while(nil, fn day_offset, _acc ->
      date = Date.add(start_date, day_offset)

      result =
        case kind do
          :sunrise ->
            Astro.sunrise(location, date,
              time_zone: timezone,
              time_zone_database: Tzdata.TimeZoneDatabase
            )

          :sunset ->
            Astro.sunset(location, date,
              time_zone: timezone,
              time_zone_database: Tzdata.TimeZoneDatabase
            )
        end

      case result do
        {:ok, dt0} ->
          dt = DateTime.add(dt0, offset_min * 60, :second)

          if DateTime.compare(dt, now) == :gt do
            {:halt, {:ok, dt}}
          else
            {:cont, nil}
          end

        {:error, :no_time} ->
          {:cont, nil}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, dt} -> {:ok, dt}
      {:error, reason} -> {:error, reason}
      nil -> {:error, :no_time_found}
    end
  end

  defp deliver(schedule) do
    case Process.whereis(schedule.module) do
      nil ->
        Logger.warning(
          "[Mirai.Scheduler] Automation #{inspect(schedule.module)} not running; dropping scheduled message #{inspect(schedule.message)}"
        )

      pid ->
        send(pid, {:schedule, schedule.message})
    end
  end

  defp log_next(%{kind: :every} = schedule, delay_ms, _next_at, _timezone) do
    Logger.debug(
      "[Mirai.Scheduler] Next #{inspect(schedule.module)} #{inspect(schedule.message)} in #{delay_ms}ms (every)"
    )
  end

  defp log_next(schedule, delay_ms, %DateTime{} = next_at, timezone) do
    next_local =
      case DateTime.shift_zone(next_at, timezone) do
        {:ok, dt} -> dt
        {:error, _} -> next_at
      end

    Logger.debug(
      "[Mirai.Scheduler] Next #{inspect(schedule.module)} #{inspect(schedule.message)} at #{DateTime.to_string(next_local)} (in #{delay_ms}ms)"
    )
  end
end
