defmodule Mirai.HA.Connector do
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def send_command(msg) do
    GenServer.cast(__MODULE__, {:send, msg})
  end

  def init(opts) do
    state = %{
      host: Keyword.fetch!(opts, :host) |> String.to_charlist(),
      port: Keyword.get(opts, :port, 8123),
      token: Keyword.fetch!(opts, :token),
      conn: nil,
      stream: nil,
      authenticated: false,
      msg_id: 1
    }

    # Connect async to not block startup
    send(self(), :connect)
    {:ok, state}
  end

  def handle_info(:connect, state) do
    Logger.info("Connecting to Home Assistant at #{state.host}:#{state.port}...")

    case :gun.open(state.host, state.port, %{protocols: [:http]}) do
      {:ok, conn} ->
        case :gun.await_up(conn, 10_000) do
          {:ok, :http} ->
            stream = :gun.ws_upgrade(conn, "/api/websocket")
            {:noreply, %{state | conn: conn, stream: stream}}

          {:error, reason} ->
            Logger.error("Failed to connect to HA: #{inspect(reason)}. Retrying in 5s...")
            :gun.close(conn)
            Process.send_after(self(), :connect, 5_000)
            {:noreply, state}
        end

      {:error, reason} ->
        Logger.error("Failed to open connection to HA: #{inspect(reason)}. Retrying in 5s...")
        Process.send_after(self(), :connect, 5_000)
        {:noreply, state}
    end
  end

  def handle_info({:gun_upgrade, conn, stream, ["websocket"], _headers}, state) do
    Logger.info("WebSocket upgraded successfully")
    {:noreply, %{state | conn: conn, stream: stream}}
  end

  def handle_info({:gun_ws, _conn, _stream, {:text, json}}, state) do
    msg = Jason.decode!(json)

    case msg["type"] do
      "auth_required" ->
        Logger.info("Auth required")
        auth = Jason.encode!(%{type: "auth", access_token: state.token})
        :gun.ws_send(state.conn, state.stream, {:text, auth})
        {:noreply, state}

      "auth_ok" ->
        Logger.info("Authenticated")
        subscribe_to_events(state)
        # Increment msg_id after subscribe used it
        {:noreply, %{state | authenticated: true, msg_id: state.msg_id + 1}}

      "event" ->
        Mirai.HA.Normalizer.normalize(msg)
        |> then(fn normalized ->
          Phoenix.PubSub.broadcast(Mirai.PubSub, "ha:events", {:event, normalized})
        end)

        {:noreply, state}

      "result" ->
        if msg["result"] == nil and msg["success"] == true do
          Logger.debug("Received result: nil (success) for id=#{msg["id"]}")
        else
          Logger.info("Received result: #{inspect(msg["result"])} for id=#{msg["id"]}")
        end

        {:noreply, state}

      other ->
        Logger.info("Received message: #{inspect(other)}")
        {:noreply, state}
    end
  end

  def handle_info({:gun_down, _conn, _proto, reason, _killed}, state) do
    Logger.warning("Connection went down: #{inspect(reason)}. Reconnecting in 5s...")
    Process.send_after(self(), :connect, 5_000)
    {:noreply, %{state | conn: nil, stream: nil, authenticated: false}}
  end

  def handle_cast({:send, msg}, %{authenticated: false} = state) do
    Logger.warning("Not connected to HA yet, dropping message: #{msg[:domain]}.#{msg[:service]}")
    {:noreply, state}
  end

  def handle_cast({:send, msg}, state) do
    # Assign monotonically increasing ID
    msg_with_id = Map.put(msg, :id, state.msg_id)

    Logger.debug(
      "Sending: id=#{state.msg_id} #{msg[:domain]}.#{msg[:service]} target=#{inspect(msg[:target])}"
    )

    json = Jason.encode!(msg_with_id)
    :gun.ws_send(state.conn, state.stream, {:text, json})
    {:noreply, %{state | msg_id: state.msg_id + 1}}
  end

  # Helper function to subscribe to events
  defp subscribe_to_events(state) do
    # Subscribe to ALL events
    subscribe_msg =
      Jason.encode!(%{
        id: state.msg_id,
        type: "subscribe_events",
        event_type: "state_changed"
      })

    :gun.ws_send(state.conn, state.stream, {:text, subscribe_msg})
    Logger.info("Subscribed to all Home Assistant events")

    # Or subscribe to specific event types:
    # subscribe_msg = Jason.encode!(%{
    #   id: state.msg_id,
    #   type: "subscribe_events",
    #   event_type: "state_changed"  # Only state changes
    # })
  end
end
