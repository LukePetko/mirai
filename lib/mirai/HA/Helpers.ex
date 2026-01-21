defmodule Mirai.HA.Helpers do
  @moduledoc """
  Helper functions for working with Home Assistant
  """
  alias Mirai.HA.Connector

  @doc """
  Calls a service on Home Assistant

  ## Example
      # Turn on light
      call_service("light", "turn_on", %{entity_id: "light.living_room", brightness: 255})

      # Turn off switch
      call_service("switch", "turn_off", %{entity_id: "switch.fan"})
  """
  def call_service(domain, service, data \\ %{}) do
    # Separate targeting keys from service data (HA uses target for entity/device/area selection)
    {target, service_data} = extract_target(data)

    msg = %{
      type: "call_service",
      domain: domain,
      service: service,
      service_data: service_data
    }

    # Only add target if we have targeting keys
    msg = if map_size(target) > 0, do: Map.put(msg, :target, target), else: msg

    # Let Connector assign the ID (it tracks monotonically increasing IDs)
    Connector.send_command(msg)
  end

  defp extract_target(data) do
    target_keys = [:entity_id, :device_id, :area_id, "entity_id", "device_id", "area_id"]

    Enum.reduce(target_keys, {%{}, data}, fn key, {target, remaining} ->
      case Map.pop(remaining, key) do
        {nil, remaining} ->
          {target, remaining}

        {value, remaining} ->
          # Normalize key to atom
          atom_key = if is_binary(key), do: String.to_atom(key), else: key
          {Map.put(target, atom_key, value), remaining}
      end
    end)
  end
end
