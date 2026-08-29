defmodule Mirai.Runtime.Api do
  @moduledoc false

  import Plug.Conn

  alias Mirai.Runtime

  def init(opts) do
    %{
      runtime: Keyword.get(opts, :runtime, Runtime),
      token: Keyword.fetch!(opts, :token)
    }
  end

  def call(conn, opts) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    if authorized?(conn, opts.token) do
      dispatch(conn, opts.runtime)
    else
      json(conn, 401, %{error: "unauthorized"})
    end
  end

  defp dispatch(%{method: "GET", request_path: "/v1/snapshot"} = conn, runtime) do
    runtime
    |> Runtime.snapshot()
    |> external_snapshot()
    |> then(&json(conn, 200, &1))
  end

  defp dispatch(%{method: "GET", request_path: "/health"} = conn, _runtime) do
    json(conn, 200, %{status: "ok"})
  end

  defp dispatch(conn, _runtime), do: json(conn, 404, %{error: "not_found"})

  defp authorized?(conn, expected) do
    with ["Bearer " <> presented] <- get_req_header(conn, "authorization"),
         true <- byte_size(presented) == byte_size(expected) do
      Plug.Crypto.secure_compare(presented, expected)
    else
      _unauthorized -> false
    end
  end

  defp external_snapshot(snapshot) do
    %{
      source: snapshot.source,
      capturedAt: snapshot.captured_at,
      runtime: %{
        name: snapshot.runtime.name,
        status: snapshot.runtime.status,
        uptimeSeconds: snapshot.runtime.uptime_seconds,
        version: snapshot.runtime.version
      },
      homeAssistant: %{
        status: snapshot.home_assistant.status,
        cachedStates: snapshot.home_assistant.cached_states
      },
      deployment: snapshot.deployment,
      metrics: %{
        loadedAutomations: snapshot.metrics.loaded_automations,
        expectedAutomations: snapshot.metrics.expected_automations,
        eventsPerMinute: snapshot.metrics.events_per_minute
      },
      automations:
        Enum.map(snapshot.automations, fn automation ->
          %{
            id: automation.id,
            name: automation.name,
            target: automation.target || "not reported",
            status: automation.status,
            lastRunAt: automation.last_run_at,
            durationMs: automation.duration_ms
          }
        end),
      events:
        Enum.map(snapshot.events, fn event ->
          %{
            id: event.id,
            occurredAt: event.occurred_at,
            source: event.source,
            message: event.message,
            level: event.level
          }
        end)
    }
  end

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
