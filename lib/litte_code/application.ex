defmodule LitteCode.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      LitteCodeWeb.Telemetry,
      LitteCode.Repo,
      {DNSCluster, query: Application.get_env(:litte_code, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: LitteCode.PubSub},
      # Start a worker by calling: LitteCode.Worker.start_link(arg)
      # {LitteCode.Worker, arg},
      # Start to serve requests, typically the last entry
      LitteCodeWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LitteCode.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LitteCodeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
