defmodule Mirai.MQTT.Connector do
  use GenServer
  require Logger
  alias Tortoise.{Connection, Transport}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def publish(topic, payload, opts \\ []) do
    qos = Keyword.get(opts, :qos, 0)
    GenServer.cast(__MODULE__, {:publish, topic, payload, qos})
  end

  def init(opts) do
    state = %{
      host: Keyword.fetch!(opts, :host) |> String.to_charlist(),
      port: Keyword.get(opts, :port, 1883),
      client_id: Keyword.fetch!(opts, :client_id),
      topics: [
        {"pomodoro/timer/+", 0}
      ]
    }

    {:ok, pid} =
      Connection.start_link(
        client_id: state.client_id,
        server: {Transport.Tcp, host: state.host, port: state.port},
        handler: {Mirai.MQTT.Handler, []}
      )

    Logger.info("Connected to MQTT broker at #{state.host}:#{state.port}")

    Connection.subscribe(state.client_id, state.topics)

    {:ok, Map.put(state, :connection, pid)}
  end

  def handle_info({{Tortoise, _client_id}, _ref, :ok}, state) do
    Logger.debug("MQTT subscription confirmed")
    {:noreply, state}
  end

  def handle_info({{Tortoise, _client_id}, _ref, result}, state) do
    Logger.debug("MQTT operation result: #{inspect(result)}")
    {:noreply, state}
  end

  def handle_cast({:publish, topic, payload, qos}, state) do
    Tortoise.publish(state.client_id, topic, payload, qos: qos)
    {:noreply, state}
  end
end
