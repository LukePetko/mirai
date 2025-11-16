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
    {:ok, %{}}
  end

  def handle_cast({:trigger, event}, state) do
    Logger.info("Triggered event: #{inspect(event)}")
    {:noreply, state}
  end
end
