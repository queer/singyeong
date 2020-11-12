defmodule Singyeong.Application do
  @moduledoc false

  use Application
  alias Singyeong.{Config, PluginManager, Utils}
  require Logger

  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec

    PluginManager.init()

    # Define workers and child supervisors to be supervised
    children = [
      # Task supervisor
      {Task.Supervisor, name: Singyeong.TaskSupervisor},
      {DynamicSupervisor, strategy: :one_for_one, name: Singyeong.MetadataQueueSupervisor},
    ]
    # Add clustering children if needed
    children =
      if Config.clustering() == "true" do
        Logger.info "[APP] Clustering enabled, setting up Redis and cluster workers..."
        Utils.fast_list_concat children, [
          # Redis worker pool
          Singyeong.Redis,
          # Clustering worker
          Singyeong.Cluster
        ]
      else
        # Doesn't need a supervisor, hence doing it like this
        # We initialize it here because the clustering worker takes care of
        # initializing Mnesia *after* starting the local node.
        Singyeong.Store.start()

        children
      end
    # Load plugins and add their behaviours to the supervision tree
    children = Utils.fast_list_concat children, PluginManager.load_plugins()
    # Configure pubsub so that phx will be happy
    children = Utils.fast_list_concat children, {Phoenix.PubSub, [name: Singyeong.PubSub, adapter: Phoenix.PubSub.PG2]}
    # Finally, add endpoint supervisor
    children = Utils.fast_list_concat children, [supervisor(SingyeongWeb.Endpoint, [])]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Singyeong.Supervisor]
    Supervisor.start_link children, opts
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    SingyeongWeb.Endpoint.config_change changed, removed
    :ok
  end
end
