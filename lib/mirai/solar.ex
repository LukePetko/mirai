defmodule Mirai.Solar do
  @moduledoc """
  Helpers for calculating sunrise/sunset-based time windows.

  These calculations are local and use the same Astro/Tzdata setup as the scheduler.
  Location is read from `MIRAI_LATITUDE`, `MIRAI_LONGITUDE`, and `MIRAI_TIMEZONE`
  unless provided explicitly.
  """

  require Logger

  @doc """
  Returns whether the current local time is between sunset and the following sunrise.

  Options:
  - `:sunset_offset` - minutes added to sunset (negative means before sunset)
  - `:sunrise_offset` - minutes added to sunrise
  - `:latitude` - override latitude
  - `:longitude` - override longitude
  - `:timezone` - override timezone
  - `:now` - override current datetime (useful for tests)
  """
  def between_sunset_and_sunrise?(opts \\ []) do
    timezone =
      normalize_timezone(
        Keyword.get(opts, :timezone, System.get_env("MIRAI_TIMEZONE", "Europe/Prague"))
      )

    location =
      normalize_location(
        Keyword.get(opts, :latitude, parse_float(System.get_env("MIRAI_LATITUDE"))),
        Keyword.get(opts, :longitude, parse_float(System.get_env("MIRAI_LONGITUDE")))
      )

    now = local_now(Keyword.get(opts, :now), timezone)
    date = DateTime.to_date(now)
    sunset_offset = Keyword.get(opts, :sunset_offset, 0)
    sunrise_offset = Keyword.get(opts, :sunrise_offset, 0)

    with {lng, lat} = location when is_number(lat) and is_number(lng) <- location,
         {:ok, sunrise} <- solar_event(:sunrise, location, date, sunrise_offset, timezone),
         {:ok, sunset} <- solar_event(:sunset, location, date, sunset_offset, timezone) do
      DateTime.compare(now, sunrise) == :lt or DateTime.compare(now, sunset) != :lt
    else
      nil ->
        Logger.warning("[Mirai.Solar] Missing location, cannot evaluate solar window")
        false

      {:error, reason} ->
        Logger.warning("[Mirai.Solar] Could not evaluate solar window: #{inspect(reason)}")
        false
    end
  end

  @doc """
  Returns whether the current local time is between sunrise and the following sunset.

  Options:
  - `:sunrise_offset` - minutes added to sunrise
  - `:sunset_offset` - minutes added to sunset
  - `:latitude` - override latitude
  - `:longitude` - override longitude
  - `:timezone` - override timezone
  - `:now` - override current datetime (useful for tests)
  """
  def between_sunrise_and_sunset?(opts \\ []) do
    not between_sunset_and_sunrise?(opts)
  end

  defp solar_event(kind, location, date, offset_min, timezone) do
    datetime = local_datetime_for(date, ~T[12:00:00], timezone)

    result =
      case kind do
        :sunrise ->
          Astro.sunrise(location, datetime,
            time_zone: timezone,
            time_zone_database: Tzdata.TimeZoneDatabase
          )

        :sunset ->
          Astro.sunset(location, datetime,
            time_zone: timezone,
            time_zone_database: Tzdata.TimeZoneDatabase
          )
      end

    case result do
      {:ok, dt} -> {:ok, DateTime.add(dt, offset_min * 60, :second)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp local_now(%DateTime{} = now, timezone) do
    case DateTime.shift_zone(now, timezone) do
      {:ok, local} -> local
      {:error, _} -> now
    end
  end

  defp local_now(nil, timezone) do
    utc = DateTime.utc_now()

    case DateTime.shift_zone(utc, timezone) do
      {:ok, local} -> local
      {:error, _} -> utc
    end
  end

  defp normalize_timezone(tz) when is_binary(tz) do
    tz = String.trim(tz)

    case tz do
      "" ->
        "Etc/UTC"

      _ ->
        case DateTime.shift_zone(DateTime.utc_now(), tz) do
          {:ok, _} -> tz
          {:error, _} -> "Etc/UTC"
        end
    end
  end

  defp normalize_timezone(_), do: "Etc/UTC"

  defp local_datetime_for(date, time, timezone) do
    naive = NaiveDateTime.new!(date, time)

    case DateTime.from_naive(naive, timezone, Tzdata.TimeZoneDatabase) do
      {:ok, dt} -> dt
      {:ambiguous, _dt1, dt2} -> dt2
      {:gap, _dt1, dt2} -> dt2
      {:error, _} -> DateTime.from_naive!(naive, "Etc/UTC")
    end
  end

  defp normalize_location(lat, lng) when is_number(lat) and is_number(lng), do: {lng, lat}
  defp normalize_location(_lat, _lng), do: nil

  defp parse_float(nil), do: nil

  defp parse_float(value) when is_float(value), do: value

  defp parse_float(value) when is_integer(value), do: value * 1.0

  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {parsed, _} -> parsed
      :error -> nil
    end
  end

  defp parse_float(_), do: nil
end
