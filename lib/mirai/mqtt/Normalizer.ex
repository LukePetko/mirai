defmodule Mirai.MQTT.Normalizer do
  alias Mirai.Event

  def normalize(topic_parts, payload) do
    topic = Enum.join(topic_parts, "/")

    parsed = case Jason.decode(payload) do
      {:ok, decoded} -> decoded
      _ -> %{"raw" => to_string(payload)}
    end

    Event.new(%{
      id: "mqtt_#{System.unique_integer([:positive, :monotonic])}",
      source: :mqtt,
      type: :state_changed,
      timestamp: DateTime.utc_now(),
      entity_id: topic,
      domain: "mqtt",
      new_state: %{state: parsed},
      old_state: nil,
      attributes: parsed,
      context: %{},
      event: %{},
      raw: %{topic: topic, payload: payload}
    })
  end
end
