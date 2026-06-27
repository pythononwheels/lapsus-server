defmodule LapsusCoordinator.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      LapsusCoordinatorWeb.Telemetry,
      LapsusCoordinator.Repo,
      {Ecto.Migrator,
        repos: Application.fetch_env!(:lapsus_coordinator, :ecto_repos),
        skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:lapsus_coordinator, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: LapsusCoordinator.PubSub},
      LapsusCoordinator.Presence,
      # Start a worker by calling: LapsusCoordinator.Worker.start_link(arg)
      # {LapsusCoordinator.Worker, arg},
      # Start to serve requests, typically the last entry
      LapsusCoordinatorWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LapsusCoordinator.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LapsusCoordinatorWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # Run migrations on boot in all environments, including releases — the
    # coordinator is a single-node SQLite service, so boot-time migration is
    # the simplest correct approach (idempotent).
    false
  end
end
