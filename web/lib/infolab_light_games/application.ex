defmodule InfolabLightGames.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      InfolabLightGamesWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: InfolabLightGames.PubSub},
      # Start the Endpoint (http/https)
      Presence,
      InfolabLightGamesWeb.Endpoint,
      # Start a worker by calling: InfolabLightGames.Worker.start_link(arg)
      # {InfolabLightGames.Worker, arg}
      GameSupervisor,
      Screen,
      Coordinator,
      Bans,
      MatrixPow,
      Scheduler
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: InfolabLightGames.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    InfolabLightGamesWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
