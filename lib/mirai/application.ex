defmodule Mirai.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    automations = discover_and_compile_automations()

    children = [
      {Phoenix.PubSub, name: Mirai.PubSub},
      {Mirai.HA.Connector,
       host: System.get_env("HA_HOST", "homeassistant.local"),
       port: String.to_integer(System.get_env("HA_PORT", "8123")),
       token: System.get_env("HA_TOKEN")},
      {Mirai.AutomationEngine, []}
      # Starts a worker by calling: Mirai.Worker.start_link(arg)
      # {Mirai.Worker, arg}
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
        end)
      
      {:error, _} -> []
    end
  end
end
