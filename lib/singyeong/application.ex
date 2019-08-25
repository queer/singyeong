defmodule Singyeong.Application do
  @moduledoc false

  alias Singyeong.Env
  use Application
  require Logger

  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec

    # Define workers and child supervisors to be supervised
    children = [
      # Task supervisor
      {Task.Supervisor, name: Singyeong.TaskSupervisor},
      {DynamicSupervisor, strategy: :one_for_one, name: Singyeong.MetadataQueueSupervisor},
    ]
    # Add clustering children if needed
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
        # Doesn't need a supervisor, hence doing it like this
        # We initialize it here because the clustering worker takes care of
        # initializing Mnesia *after* starting the local node.
        Singyeong.MnesiaStore.initialize()

        children
      end
    # Finally, add endpoint supervisor
    children = children ++ [supervisor(SingyeongWeb.Endpoint, [])]

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
