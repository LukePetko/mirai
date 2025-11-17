defmodule Mirai.HA.Normalizer do
  @moduledoc """
  Normalizes the incoming JSON from Home Assistant.
  """

  alias Mirai.Event

  def normalize(%{"type" => "event", "event" => event_data} = message) do
    event_type = classify_event(event_data)

    base_params = %{
      id: generate_event_id(event_data),
      type: event_type,
      source: :home_assistant,
      timestamp: parse_timestamp(event_data),
      raw: message
    }

    case event_type do
      :state_change -> normalize_state_change(event_data, base_params)
      :service_call -> normalize_service_call(event_data, base_params)
      _ -> Event.new(base_params)
    end
  end

  defp classify_event(%{"event_type" => "state_changed"}), do: :state_change
  defp classify_event(%{"event_type" => "call_service"}), do: :service_call
  defp classify_event(%{"event_type" => "automation_triggered"}), do: :automation_trigger
  defp classify_event(_), do: :unknown

  defp normalize_state_change(event_data, base_params) do
    data = event_data["data"] || %{}
    entity_id = data["entity_id"]

    Event.new(
      Map.merge(base_params, %{
        entity_id: entity_id,
        domain: Event.extract_domain(entity_id),
        old_state: extract_state(data["old_state"]),
        new_state: extract_state(data["new_state"]),
        attributes: extract_attributes(data["new_state"]),
        context: event_data["context"] || %{}
      })
    )
  end

  defp extract_state(nil), do: nil

  defp extract_state(state) do
    %{
      state: state["state"],
      last_changed: state["last_changed"],
      last_updated: state["last_updated"]
    }
  end

  defp extract_attributes(nil), do: %{}

  defp extract_attributes(state) do
    state["attributes"] || %{}
  end

  defp parse_timestamp(%{"time_fired" => time_str}) when is_binary(time_str) do
    case DateTime.from_iso8601(time_str) do
      {:ok, dt, _offset} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp parse_timestamp(_), do: DateTime.utc_now()

  defp normalize_service_call(event_data, base_params) do
    data = event_data["data"] || %{}

    Event.new(
      Map.merge(base_params, %{
        domain: data["domain"],
        attributes: %{
          service: data["service"],
          service_data: data["service_data"]
        },
        context: event_data["context"] || %{}
      })
    )
  end

  defp generate_event_id(%{"id" => id}), do: "ha_#{id}"

  defp generate_event_id(_) do
    "ha_#{System.unique_integer([:positive, :monotonic])}"
  end
end
