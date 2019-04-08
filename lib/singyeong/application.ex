defmodule Singyeong.Application do
  alias Singyeong.Env
  use Application
  require Logger

  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec

    # Doesn't need a supervisor, hence doing it like this
    Singyeong.MnesiaStore.initialize()

    # Define workers and child supervisors to be supervised
    children = [
      # Start the endpoint when the application starts
      supervisor(SingyeongWeb.Endpoint, []),
      # Task supervisor
      {Task.Supervisor, name: Singyeong.TaskSupervisor},
    ]
    children =
      if Env.clustering() == "true" do
        Logger.info "[APP] Clustering enabled, setting up Redis and cluster workers..."
        children ++ [
          # Redis worker pool
          Singyeong.Redis,
          # Clustering worker
          Singyeong.Cluster
        ]
      else
        children
      end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Singyeong.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    SingyeongWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
