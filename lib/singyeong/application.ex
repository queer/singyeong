defmodule Singyeong.Application do
  @moduledoc false

  use Application
  alias Singyeong.{Config, PluginManager, Store, Utils}
  require Logger

  def start(_type, _args) do
    unless Node.alive?() do
      node_name =
        32
        |> Utils.random_string
        |> String.to_atom

      Logger.info "[APP] No node, booting @ #{node_name}"

      Node.start node_name, :shortnames
      Node.set_cookie Node.self(), Config.node_cookie()
    end
    PluginManager.init()
    # TODO: Correct place to start this?
    Store.start()

    # topologies = Application.get_env :singyeong, :topologies
    topologies = [
      singyeong: [
        strategy: Cluster.Strategy.Gossip
      ]
    ]
    children = [
      # Task supervisor
      {Cluster.Supervisor, [topologies, [name: Singyeong.ClusterSupervisor]]},
      Singyeong.Cluster,
      {Task.Supervisor, name: Singyeong.TaskSupervisor},
      {DynamicSupervisor, strategy: :one_for_one, name: Singyeong.MetadataQueueSupervisor},
      {DynamicSupervisor, strategy: :one_for_one, name: Singyeong.QueueGcSupervisor},
    ]

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
