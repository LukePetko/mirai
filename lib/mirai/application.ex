defmodule Mirai.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    automations = discover_and_compile_automations()

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
      ] ++ Enum.map(automations, fn automation -> {automation, []} end)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Mirai.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp discover_and_compile_automations do
    automations_path = Path.join(:code.priv_dir(:mirai), "automations")

    case File.ls(automations_path) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".ex"))
        |> Enum.flat_map(fn file ->
          file_path = Path.join(automations_path, file)

          Code.compile_file(file_path)
          |> Enum.map(fn {mod, _} -> mod end)
          |> Enum.filter(&is_automation?/1)
        end)

      {:error, _} ->
        []
    end
  end

  # Only start modules that use Mirai.Automation (have start_link/1)
  defp is_automation?(module) do
    function_exported?(module, :start_link, 1)
  end
end
