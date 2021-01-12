defmodule Singyeong.Application do
  @moduledoc false

  use Application
  alias Singyeong.{Config, PluginManager, Store, Utils}
  require Logger

  def start(_type, _args) do
    PluginManager.init()
    # TODO: Correct place to start this?
    Store.start()

    children = [
      # Task supervisor
      {Task.Supervisor, name: Singyeong.TaskSupervisor},
      {DynamicSupervisor, strategy: :one_for_one, name: Singyeong.MetadataQueueSupervisor},
      {DynamicSupervisor, strategy: :one_for_one, name: Singyeong.QueueGcSupervisor},
    ]
    # Add clustering children if needed
    children =
      if Config.clustering() == "true" do
        Logger.info "[APP] Clustering enabled, setting up Redis and cluster workers..."
        Utils.fast_list_concat children, [
          Singyeong.Redis,
          Singyeong.Cluster
        ]
      else
        children
      end

    # Load plugins and add their behaviours to the supervision tree
    children = Utils.fast_list_concat children, PluginManager.load_plugins()
    # Configure pubsub so that phx will be happy
    children = Utils.fast_list_concat children, {Phoenix.PubSub, [name: Singyeong.PubSub, adapter: Phoenix.PubSub.PG2]}
    # Finally, add endpoint supervisor
    children = Utils.fast_list_concat children, [SingyeongWeb.Endpoint]

    opts = [strategy: :one_for_one, name: Singyeong.Supervisor]
    Supervisor.start_link children, opts
  end

  def config_change(changed, _new, removed) do
    SingyeongWeb.Endpoint.config_change changed, removed
    :ok
  end
end
