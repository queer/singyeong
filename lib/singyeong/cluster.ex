defmodule Singyeong.Cluster do
  @moduledoc """
  Adapted from https://github.com/queer/lace/blob/master/lib/lace.ex

  TODO: Wouldn't it make more sense to just use a set instead of a hash in
    Redis?
  """

  use GenServer
  alias Singyeong.Discovery
  alias Singyeong.Env
  alias Singyeong.Metadata.Query
  alias Singyeong.Redis
  require Logger

  @start_delay 50
  @connect_interval 1000
  @fake_local_node :singyeong_local_node

  #######################
  # GenServer callbacks #
  #######################

  def start_link(opts) do
    GenServer.start_link __MODULE__, opts
  end

  def init(_) do
    hostname = get_hostname()
    ip = get_hostaddr()
    hash =
      :crypto.hash(:md5, :os.system_time(:millisecond)
      |> Integer.to_string)
      |> Base.encode16
      |> String.downcase
    state = %{
      name: "singyeong_#{get_hostname()}_#{Env.port()}",
      group: "singyeong",
      cookie: Env.cookie(),
      longname: nil,
      hostname: hostname,
      ip: ip,
      hash: hash,
    }
    # Start clustering after a smol delay
    Process.send_after self(), :start_connect, @start_delay
    {:ok, state}
  end

  def handle_info(:start_connect, state) do
    unless Node.alive? do
      node_name = "#{state[:name]}@#{state[:ip]}"
      node_atom = node_name |> String.to_atom

      Logger.info "[CLUSTER] Starting node: #{node_name}"
      {:ok, _} = Node.start node_atom, :longnames
      Node.set_cookie state[:cookie] |> String.to_atom

      Logger.info "[CLUSTER] Bootstrapping Mnesia..."
      Singyeong.MnesiaStore.initialize()

      Logger.info "[CLUSTER] Updating registry..."
      new_state = %{state | longname: node_name}
      registry_write new_state

      Logger.info "[CLUSTER] All done! Starting clustering..."
      Process.send_after self(), :connect, @start_delay

      {:noreply, new_state}
    else
      Logger.warn "[CLUSTER] Node already alive, doing nothing..."
      {:noreply, state}
    end
  end

  def handle_info(:connect, state) do
    registry_write state
    nodes = registry_read state

    for node <- nodes do
      {hash, longname} = node

      unless hash == state[:hash] do
        atom = longname |> String.to_atom
        case Node.connect(atom) do
          true ->
            # TODO: How to handle this case?
            # Don't need to do anything else
            # This is NOT logged at :info to avoid spamme
            # Logger.debug "[CLUSTER] Connected to #{longname}"
            ""
          false ->
            # If we can't connect, prune it from the registry. If the remote
            # node is still alive, it'll re-register itself.
            delete_node state, hash, longname
          :ignored ->
            # TODO: How to handle this case?
            # In general we shouldn't reach it, so...
            # Logger.debug "[CLUSTER] [CONCERN] Local node not alive for #{longname}!?"
            ""
        end
      end
    end
    # TODO: This should probably be a TRACE, but Elixir doesn't seem to have that :C
    # Could be useful for debuggo I guess?
    # Logger.debug "[CLUSTER] Connected to: #{inspect Node.list()}"

    # Do this again, forever.
    Process.send_after self(), :connect, @connect_interval

    {:noreply, state}
  end

  ##########################
  # Cluster-wide functions #
  ##########################

  @doc """
  Discover a service name based off of tags across the entire 신경 cluster.
  """
  def discover(tags) do
    run_clustered fn ->
      Discovery.discover_service tags
    end
  end

  @doc """
  Run a metadata query across the entire cluster, and return a mapping of nodes
  to matching client ids.
  """
  def query(query) do
    run_clustered fn ->
      Query.run_query query
    end
  end

  defp run_clustered(func) do
    # Wrap the local function into a
    local_func = fn ->
      res = func.()
      {@fake_local_node, res}
    end
    local_task = Task.Supervisor.async Singyeong.TaskSupervisor, local_func
    tasks = [local_task]
    Node.list()
    |> Enum.reduce(tasks, fn(node, acc) ->
      task =
        Task.Supervisor.async {Singyeong.TaskSupervisor, node}, fn ->
          res = func.()
          {node, res}
        end
      acc ++ [task]
    end)
    |> Enum.map(&Task.await/1)
    |> Enum.reduce(%{}, fn(res, acc) ->
      # We should never have same-named nodes so it's nbd
      {node, task_result} = res
      acc |> Map.put(node, task_result)
    end)
  end

  ######################
  # Clustering helpers #
  ######################

  defp delete_node(state, hash, longname) do
    Logger.debug "[CLUSTER] [WARN] Couldn't connect to #{longname} (#{hash}), deleting..."
    reg = registry_name state[:group]
    {:ok, _} = Redis.q ["HDEL", reg, hash]
    :ok
  end

  defp get_network_state do
    {:ok, hostname} = :inet.gethostname()
    {:ok, hostaddr} = :inet.getaddr(hostname, :inet)
    hostaddr =
      hostaddr
      |> Tuple.to_list
      |> Enum.join(".")
    %{
      hostname: to_string(hostname),
      hostaddr: hostaddr
    }
  end

  def get_hostname do
    get_network_state()[:hostname]
  end

  def get_hostaddr do
    get_network_state()[:hostaddr]
  end

  # Read all members of the registry
  defp registry_read(state) do
    reg = registry_name state[:group]
    {:ok, res} = Redis.q ["HGETALL", reg]
    res
    |> Enum.chunk_every(2)
    |> Enum.map(fn [a, b] -> {a, b} end)
    |> Enum.to_list
  end

  # Write ourself to the registry
  defp registry_write(state) do
    reg = registry_name state[:group]
    Redis.q ["HSET", reg, state[:hash], state[:longname]]
  end

  defp registry_name(name) do
    "singyeong:cluster:registry:#{name}"
  end

  def is_clustered? do
    Env.clustering() == "true"
  end

  def fake_local_node, do: @fake_local_node
end
