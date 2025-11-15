defmodule Mirai.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Mirai.HAConnection,
       host: System.get_env("HA_HOST", "homeassistant.local"),
       port: String.to_integer(System.get_env("HA_PORT", "8123")),
       token: System.get_env("HA_TOKEN")}
      # Starts a worker by calling: Mirai.Worker.start_link(arg)
      # {Mirai.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Mirai.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
