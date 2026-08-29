defmodule Mirai.HA.Connector do
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def send_command(msg) do
    GenServer.cast(__MODULE__, {:send, msg})
  end

  @doc "Returns sanitized Home Assistant connection health."
  def status(timeout \\ 250) do
    GenServer.call(__MODULE__, :status, timeout)
  end

  def init(opts) do
    state = %{
      host: Keyword.fetch!(opts, :host) |> String.to_charlist(),
      port: Keyword.get(opts, :port, 8123),
      token: Keyword.fetch!(opts, :token),
      conn: nil,
      stream: nil,
      authenticated: false,
      msg_id: 1,
      pending: %{},
      runtime: Keyword.get(opts, :runtime, Mirai.Runtime)
    }

    # Connect async to not block startup
    send(self(), :connect)
    {:ok, state}
  end

  def handle_call(:status, _from, state) do
    status =
      cond do
        state.authenticated -> "online"
        state.conn -> "degraded"
        true -> "offline"
      end

    {:reply, %{status: status}, state}
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

        {:noreply, complete_runtime_action(msg, state)}

      other ->
        Logger.info("Received message: #{inspect(other)}")
        {:noreply, state}
    end
  end

  def handle_info({:gun_ws, _conn, _stream, {:close, _code, _reason}}, state) do
    Process.send_after(self(), :connect, 5_000)
    {:noreply, disconnect(state)}
  end

  def handle_info({:gun_down, _conn, _proto, reason, _killed}, state) do
    Logger.warning("Connection went down: #{inspect(reason)}. Reconnecting in 5s...")
    Process.send_after(self(), :connect, 5_000)
    {:noreply, disconnect(state)}
  end

  def handle_info({:runtime_action_timeout, id}, state) do
    case Map.pop(state.pending, id) do
      {nil, pending} ->
        {:noreply, %{state | pending: pending}}

      {action, pending} ->
        Mirai.Runtime.record_error(action.source, "service response", state.runtime)
        {:noreply, %{state | pending: pending}}
    end
  end

  def handle_cast({:send, msg}, %{authenticated: false} = state) do
    {runtime, outbound} = runtime_metadata(msg)

    Logger.warning(
      "Not connected to HA yet, dropping message: #{outbound[:domain]}.#{outbound[:service]}"
    )

    if tracked_source?(runtime.source) do
      Mirai.Runtime.record_error(runtime.source, "service dispatch", state.runtime)
    end

    {:noreply, state}
  end

  def handle_cast({:send, msg}, state) do
    {runtime, outbound} = runtime_metadata(msg)
    msg_with_id = Map.put(outbound, :id, state.msg_id)

    Logger.debug(
      "Sending: id=#{state.msg_id} #{outbound[:domain]}.#{outbound[:service]} target=#{inspect(outbound[:target])}"
    )

    json = Jason.encode!(msg_with_id)
    :gun.ws_send(state.conn, state.stream, {:text, json})

    pending =
      if tracked_source?(runtime.source) do
        timer = Process.send_after(self(), {:runtime_action_timeout, state.msg_id}, 30_000)

        Map.put(state.pending, state.msg_id, %{
          source: runtime.source,
          service: runtime.service,
          target: runtime.target,
          started_at: System.monotonic_time(:millisecond),
          timer: timer
        })
      else
        state.pending
      end

    {:noreply, %{state | msg_id: state.msg_id + 1, pending: pending}}
  end

  defp complete_runtime_action(msg, state) do
    case Map.pop(state.pending, msg["id"]) do
      {nil, pending} ->
        %{state | pending: pending}

      {action, pending} ->
        Process.cancel_timer(action.timer)

        if msg["success"] == true do
          duration = System.monotonic_time(:millisecond) - action.started_at

          Mirai.Runtime.record_action(
            action.source,
            action.service,
            action.target,
            duration,
            state.runtime
          )
        else
          Mirai.Runtime.record_error(action.source, "service call", state.runtime)
        end

        %{state | pending: pending}
    end
  end

  defp disconnect(state) do
    Enum.each(state.pending, fn {_id, action} ->
      Process.cancel_timer(action.timer)
      Mirai.Runtime.record_error(action.source, "service response", state.runtime)
    end)

    %{state | conn: nil, stream: nil, authenticated: false, pending: %{}}
  end

  defp runtime_metadata(msg) do
    runtime = %{
      source: msg[:_runtime_source],
      target: msg[:_runtime_target],
      service: "#{msg[:domain]}.#{msg[:service]}"
    }

    {runtime, Map.drop(msg, [:_runtime_source, :_runtime_target])}
  end

  defp tracked_source?(source) when is_atom(source) do
    function_exported?(source, :__mirai_automation__, 0) and source.__mirai_automation__()
  end

  defp tracked_source?(_source), do: false

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
