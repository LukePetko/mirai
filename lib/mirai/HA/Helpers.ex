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
  def call_sevice(domain, service, service_data \\ %{}) do
    msg = %{
      id: :erlang.unique_integer([:positive]),
      type: "call_service",
      domain: domain,
      service: service,
      service_data: service_data
    }

    Connector.send_command(msg)
  end
end
