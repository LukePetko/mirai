defmodule Mirai.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Required for DateTime.shift_zone/2 (eg "Europe/Prague").
    Calendar.put_time_zone_database(Tzdata.TimeZoneDatabase)

    automations = discover_and_compile_automations()

    scheduler_opts = [
      automations: automations,
      latitude: parse_float(System.get_env("MIRAI_LATITUDE")),
      longitude: parse_float(System.get_env("MIRAI_LONGITUDE")),
      timezone: System.get_env("MIRAI_TIMEZONE", "Europe/Prague")
    ]

    ha_opts = [
      host: System.get_env("HA_HOST", "homeassistant.local"),
      port: String.to_integer(System.get_env("HA_PORT", "8123")),
      token: System.get_env("HA_TOKEN")
    ]

    mqtt_opts = [
      host: System.get_env("MQTT_HOST", "localhost"),
      port: String.to_integer(System.get_env("MQTT_PORT", "1883")),
      client_id: System.get_env("MQTT_CLIENT_ID", "mirai")
    ]

    children =
      [
        {Phoenix.PubSub, name: Mirai.PubSub},
        {Mirai.HA.Connector, ha_opts},
        {Mirai.HA.StateCache, ha_opts},
        {Mirai.MQTT.Connector, mqtt_opts},
        Mirai.GlobalState
      ] ++
        Enum.map(automations, fn automation -> {automation, []} end) ++
        [{Mirai.Scheduler, scheduler_opts}]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Mirai.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp discover_and_compile_automations do
    automations_path =
      System.get_env("MIRAI_AUTOMATIONS_PATH") ||
        Path.join(:code.priv_dir(:mirai), "automations")

    automations_path
    |> automation_files()
    |> Enum.flat_map(fn file_path ->
      Code.compile_file(file_path)
      |> Enum.map(fn {mod, _} -> mod end)
      |> Enum.filter(&is_automation?/1)
    end)
  end

  @doc false
  def automation_files(automations_path) do
    automations_path
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.sort_by(fn file_path ->
      relative_path = Path.relative_to(file_path, automations_path)
      path_parts = Path.split(relative_path)

      shared? =
        String.starts_with?(Path.basename(relative_path), "shared") or
          match?(["shared" | _], path_parts)

      {if(shared?, do: 0, else: 1), relative_path}
    end)
  end

  # Only start modules that use Mirai.Automation (have start_link/1)
  defp is_automation?(module) do
    function_exported?(module, :start_link, 1)
  end

  defp parse_float(nil), do: nil

  defp parse_float(str) when is_binary(str) do
    case Float.parse(str) do
      {val, _} -> val
      :error -> nil
    end
  end
end
