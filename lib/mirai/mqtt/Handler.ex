defmodule Mirai.MQTT.Handler do
  use Tortoise.Handler
  require Logger

  def init(opts), do: {:ok, opts}

  def connection(:up, state) do
    Logger.info("[MQTT] connection established")
    {:ok, state}
  end

  def connection(:down, state) do
    Logger.info("[MQTT] connection lost")
    {:ok, state}
  end

  def connection(:terminating, state) do
    Logger.info("[MQTT] connection terminated")
    {:ok, state}
  end

  def subscription(:up, topix, state) do
    Logger.info("[MQTT] subscribed to topic #{inspect(topix)}")
    {:ok, state}
  end

  def subscription({:error, reason}, topic_filter, state) do
      Logger.error("[MQTT] failed to subscribe to topic #{inspect(topic_filter)}: #{inspect(reason)}")
      {:ok, state}
  end

  def subscription(_status, _topic, state), do: {:ok, state}

  def handle_message(topic_parts, payload, state) do
    event = Mirai.MQTT.Normalizer.normalize(topic_parts, payload)
    Phoenix.PubSub.broadcast(Mirai.PubSub, "mqtt:events", {:event, event})
    {:ok, state}
  end

  def terminate(reason, _state) do
    Logger.error("[MQTT] connection terminated: #{inspect(reason)}")
    :ok
  end
end

