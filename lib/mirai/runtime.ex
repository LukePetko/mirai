defmodule Mirai.Runtime do
  @moduledoc """
  Collects sanitized runtime facts for local operational tooling.

  History is bounded and held in memory. Credentials, exception details, and arbitrary automation
  state are never included in snapshots.
  """

  use GenServer

  alias Mirai.HA.{Connector, StateCache}

  @default_max_events 200
  @max_service_length 120
  @max_target_length 256
  @max_context_length 80

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def record_action(source, service, target, duration_ms) do
    record_action(source, service, target, duration_ms, __MODULE__)
  end

  def record_action(source, service, target, duration_ms, server) do
    GenServer.cast(server, {:record_action, source, service, target, duration_ms})
  end

  def record_error(source, context) do
    record_error(source, context, __MODULE__)
  end

  def record_error(source, context, server) do
    GenServer.cast(server, {:record_error, source, context})
  end

  def snapshot, do: snapshot(__MODULE__)

  def snapshot(server) do
    GenServer.call(server, :snapshot)
  end

  @impl true
  def init(opts) do
    automations =
      opts
      |> Keyword.get(:automations, [])
      |> Map.new(fn module ->
        {module,
         %{
           id: module_id(module),
           name: module_name(module),
           target: nil,
           last_run_at: nil,
           duration_ms: nil,
           last_error_at: nil
         }}
      end)

    {:ok,
     %{
       automations: automations,
       events: [],
       max_events: max(Keyword.get(opts, :max_events, @default_max_events), 0),
       started_at: System.monotonic_time(:second)
     }}
  end

  @impl true
  def handle_cast({:record_action, source, service, target, duration_ms}, state) do
    if Map.has_key?(state.automations, source) do
      occurred_at = timestamp()
      source_name = module_name(source)
      normalized_service = bounded_text(service, @max_service_length)
      normalized_target = normalize_target(target)

      event = %{
        id: event_id(),
        occurred_at: occurred_at,
        source: source_name,
        message: action_message(normalized_service, normalized_target),
        level: "success"
      }

      automations =
        Map.update!(state.automations, source, fn descriptor ->
          %{
            descriptor
            | target: normalized_target,
              last_run_at: occurred_at,
              duration_ms: normalize_duration(duration_ms),
              last_error_at: nil
          }
        end)

      {:noreply, %{state | automations: automations, events: push_event(state, event)}}
    else
      {:noreply, state}
    end
  end

  def handle_cast({:record_error, source, context}, state) do
    if Map.has_key?(state.automations, source) do
      occurred_at = timestamp()
      source_name = module_name(source)
      safe_context = bounded_text(context, @max_context_length)

      event = %{
        id: event_id(),
        occurred_at: occurred_at,
        source: source_name,
        message: "#{safe_context} failed",
        level: "error"
      }

      automations =
        Map.update!(state.automations, source, fn descriptor ->
          %{descriptor | last_error_at: occurred_at}
        end)

      {:noreply, %{state | automations: automations, events: push_event(state, event)}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    captured_at = timestamp()
    automations = automation_summaries(state.automations)
    loaded = Enum.count(automations, &(&1.status != "stopped"))

    snapshot = %{
      source: "runtime",
      captured_at: captured_at,
      runtime: %{
        name: System.get_env("MIRAI_NODE_NAME", "mirai"),
        status: "online",
        uptime_seconds: System.monotonic_time(:second) - state.started_at,
        version: application_version()
      },
      home_assistant: home_assistant_status(),
      deployment: %{
        branch: System.get_env("MIRAI_AUTOMATIONS_BRANCH"),
        commit: System.get_env("MIRAI_AUTOMATIONS_COMMIT")
      },
      metrics: %{
        loaded_automations: loaded,
        expected_automations: map_size(state.automations),
        events_per_minute: recent_event_rate(state.events, captured_at)
      },
      automations: automations,
      events: state.events
    }

    {:reply, snapshot, state}
  end

  defp automation_summaries(automations) do
    automations
    |> Enum.map(fn {module, descriptor} ->
      status =
        cond do
          descriptor.last_error_at -> "warning"
          alive?(module) -> "running"
          true -> "stopped"
        end

      descriptor
      |> Map.drop([:last_error_at])
      |> Map.put(:status, status)
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp home_assistant_status do
    connector = connector_status()

    %{
      status: connector.status,
      cached_states: StateCache.count()
    }
  end

  defp connector_status do
    if Process.whereis(Connector) do
      try do
        Connector.status()
      catch
        :exit, _reason -> %{status: "offline"}
      end
    else
      %{status: "offline"}
    end
  end

  defp recent_event_rate(events, captured_at) do
    {:ok, captured, _offset} = DateTime.from_iso8601(captured_at)
    cutoff = DateTime.add(captured, -60, :second)

    events
    |> Enum.count(fn event ->
      case DateTime.from_iso8601(event.occurred_at) do
        {:ok, occurred_at, _offset} -> DateTime.compare(occurred_at, cutoff) != :lt
        _error -> false
      end
    end)
    |> Kernel.*(1.0)
  end

  defp alive?(module) when is_atom(module) do
    case Process.whereis(module) do
      pid when is_pid(pid) -> Process.alive?(pid)
      nil -> false
    end
  end

  defp push_event(state, event) do
    [event | state.events]
    |> Enum.take(state.max_events)
  end

  defp module_id(module), do: module |> Module.split() |> Enum.join(".")

  defp module_name(module) do
    module
    |> Module.split()
    |> List.last()
  end

  defp normalize_target(nil), do: nil

  defp normalize_target(target) when is_binary(target),
    do: bounded_text(target, @max_target_length)

  defp normalize_target(target) when is_list(target) do
    target
    |> Enum.map(&to_string/1)
    |> Enum.join(", ")
    |> bounded_text(@max_target_length)
  end

  defp normalize_target(_target), do: "not reported"

  defp normalize_duration(duration_ms) when is_integer(duration_ms) and duration_ms >= 0,
    do: duration_ms

  defp normalize_duration(_duration_ms), do: nil

  defp bounded_text(value, max_length) do
    value
    |> to_string()
    |> String.slice(0, max_length)
  end

  defp action_message(service, nil), do: service
  defp action_message(service, target), do: "#{service} → #{target}"

  defp event_id do
    System.unique_integer([:positive, :monotonic])
    |> Integer.to_string()
  end

  defp timestamp, do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp application_version do
    case Application.spec(:mirai, :vsn) do
      nil -> nil
      version -> to_string(version)
    end
  end
end
