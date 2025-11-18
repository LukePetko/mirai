defmodule Mirai.AutomationEngine do
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def trigger(event) do
    GenServer.cast(__MODULE__, {:trigger, event})
  end

  def init(_) do
    automations = discover_automations()
    Logger.info("Discovered #{length(automations)} automations: #{inspect(automations)}")
    {:ok, %{automations: automations}}
  end

  def handle_cast({:trigger, event}, state) do
    Logger.info("Triggered event: #{inspect(event)}")

    Enum.each(state.automations, fn automation ->
      GenServer.cast(automation, {:check_event, event, self()})
    end)

    {:noreply, state}
  end

  defp discover_automations do
    automations_path = Path.join(:code.priv_dir(:mirai), "automations")

    case File.ls(automations_path) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".ex"))
        |> Enum.map(fn file ->
          file_path = Path.join(automations_path, file)
          Code.compile_file(file_path)

          module_name = file |> String.replace(".ex", "") |> Macro.camelize()
          String.to_atom(module_name)
        end)

      {:error, _} ->
        Logger.warning("No automations found in #{automations_path}")
        []
    end
  end
end
