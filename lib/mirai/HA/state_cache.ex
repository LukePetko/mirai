defmodule Mirai.HA.StateCache do
  @moduledoc """
  ETS-based cache of Home Assistant entity states.

  On startup, fetches all entity states from HA REST API.
  Then stays updated by listening to state_changed events via PubSub.

  Use `get_state/1` or `get_state!/1` to query current state of any entity.

  ## Example

      iex> Mirai.HA.StateCache.get_state("light.kitchen")
      {:ok, %{state: "on", attributes: %{brightness: 255, ...}, last_changed: ...}}

      iex> Mirai.HA.StateCache.get_state!("light.kitchen")
      %{state: "on", attributes: %{brightness: 255, ...}, last_changed: ...}
  """

  use GenServer
  require Logger

  @table :mirai_state_cache

  # --- Public API ---

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the current state of an entity.

  Returns `{:ok, state_map}` or `{:error, :not_found}`.
  """
  def get_state(entity_id) do
    case :ets.lookup(@table, entity_id) do
      [{^entity_id, state}] -> {:ok, state}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Gets the current state of an entity, raises if not found.
  """
  def get_state!(entity_id) do
    case get_state(entity_id) do
      {:ok, state} -> state
      {:error, :not_found} -> raise "Entity not found: #{entity_id}"
    end
  end

  @doc """
  Returns all cached entity IDs.
  """
  def all_entities do
    :ets.tab2list(@table)
    |> Enum.map(fn {entity_id, _state} -> entity_id end)
    |> Enum.sort()
  end

  # --- GenServer callbacks ---

  def init(opts) do
    # Create ETS table - public so helpers can read directly
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])

    # Subscribe to events to keep cache updated
    Phoenix.PubSub.subscribe(Mirai.PubSub, "ha:events")

    # Bootstrap from REST API
    host = Keyword.get(opts, :host, System.get_env("HA_HOST", "homeassistant.local"))
    port = Keyword.get(opts, :port, String.to_integer(System.get_env("HA_PORT", "8123")))
    token = Keyword.get(opts, :token, System.get_env("HA_TOKEN"))

    # Do bootstrap async so we don't block startup
    Task.start(fn -> bootstrap_states(host, port, token) end)

    {:ok, %{}}
  end

  # Update cache when state changes
  def handle_info({:event, %{type: :state_change} = event}, state) do
    update_from_event(event)
    {:noreply, state}
  end

  def handle_info({:event, _other_event}, state) do
    # Ignore non-state-change events
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # --- Private functions ---

  defp bootstrap_states(host, port, token) do
    Logger.info("[StateCache] Bootstrapping states from Home Assistant...")

    case fetch_all_states(host, port, token) do
      {:ok, states} ->
        Enum.each(states, fn state_obj ->
          entity_id = state_obj["entity_id"]
          :ets.insert(@table, {entity_id, normalize_state(state_obj)})
        end)

        Logger.info("[StateCache] Cached #{length(states)} entity states")

      {:error, reason} ->
        Logger.error("[StateCache] Failed to bootstrap states: #{inspect(reason)}")
    end
  end

  defp fetch_all_states(host, port, token) do
    host_charlist = if is_binary(host), do: String.to_charlist(host), else: host

    with {:ok, conn} <- :gun.open(host_charlist, port, %{protocols: [:http]}),
         {:ok, :http} <- :gun.await_up(conn) do
      stream =
        :gun.get(conn, "/api/states", [
          {"authorization", "Bearer #{token}"},
          {"content-type", "application/json"}
        ])

      result =
        case :gun.await(conn, stream, 10_000) do
          {:response, :fin, _status, _headers} ->
            {:error, :empty_response}

          {:response, :nofin, 200, _headers} ->
            {:ok, body} = :gun.await_body(conn, stream)
            {:ok, Jason.decode!(body)}

          {:response, :nofin, status, _headers} ->
            {:error, {:http_error, status}}

          {:error, reason} ->
            {:error, reason}
        end

      :gun.close(conn)
      result
    end
  end

  defp update_from_event(%{entity_id: entity_id, new_state: new_state, attributes: attributes}) do
    state_map = %{
      state: new_state && new_state.state,
      attributes: attributes || %{},
      last_changed: new_state && new_state.last_changed,
      last_updated: new_state && new_state.last_updated
    }

    :ets.insert(@table, {entity_id, state_map})
  end

  defp normalize_state(state_obj) do
    %{
      state: state_obj["state"],
      attributes: state_obj["attributes"] || %{},
      last_changed: state_obj["last_changed"],
      last_updated: state_obj["last_updated"]
    }
  end
end
