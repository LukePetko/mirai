defmodule Mirai.HA.Connector do
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def send_command(msg) do
    GenServer.cast(__MODULE__, {:send_command, {:send, msg}})
  end

  def init(opts) do
    host = Keyword.fetch!(opts, :host) |> String.to_charlist()
    port = Keyword.get(opts, :port, 8123)
    token = Keyword.fetch!(opts, :token)

    {:ok, conn} = :gun.open(host, port, %{protocols: [:http]})
    {:ok, :http} = :gun.await_up(conn)
    stream = :gun.ws_upgrade(conn, "/api/websocket")

    state = %{
      conn: conn,
      stream: stream,
      token: token,
      authenticated: false,
      msg_id: 1
    }

    {:ok, state}
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
        {:noreply, %{state | authenticated: true}}

      "event" ->
        Mirai.AutomationEngine.trigger(msg["event"])
        {:noreply, state}

      "result" ->
        Logger.info("Received result: #{inspect(msg["result"])}")
        {:noreply, state}

      other ->
        Logger.info("Received message: #{inspect(other)}")
        {:noreply, state}
    end
  end

  def handle_info({:gun_down, _conn, _proto, _reason, _killed}, state) do
    Logger.warning("Connection went down!")
    # In production, you'd trigger a reconnect here
    {:noreply, state}
  end

  def handle_cast({:send, msg}, state) do
    json = Jason.encode!(msg)
    :gun.ws_send(state.conn, state.stream, {:text, json})
    {:noreply, state}
  end

    # Helper function to subscribe to events
  defp subscribe_to_events(state) do
    # Subscribe to ALL events
    subscribe_msg = Jason.encode!(%{
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
