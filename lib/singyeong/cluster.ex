defmodule Singyeong.Cluster do
  @moduledoc """
  Adapted from https://github.com/queer/lace/blob/master/lib/lace.ex
  """

  use GenServer
  alias Singyeong.Config
  alias Singyeong.Gateway.Payload
  alias Singyeong.Store
  alias Singyeong.Utils
  require Logger

  @start_delay 50
  @connect_interval 1000
  @fake_local_node :singyeong_local_node

  # GENSERVER CALLBACKS #

  def start_link(opts) do
    GenServer.start_link __MODULE__, opts
  end

  def init(_) do
    state =
      %{
        rafted?: false,
        last_nodes: %{},
      }
    # Start clustering after a smol delay
    Process.send_after self(), :start_connect, @start_delay
    Logger.info "[CLUSTER] up"
    {:ok, state}
  end

  def handle_info(:start_connect, state) do
    last_nodes = Node.list()

    new_state = %{state | last_nodes: last_nodes}
    Process.send_after self(), :connect, @start_delay

    {:noreply, new_state}
  end

  def handle_info(:connect, state) do
    load_balance()

    state = update_raft_state state

    # Do this again, forever.
    Process.send_after self(), :connect, @connect_interval

    {:noreply, state}
  end

  defp load_balance do
    spawn fn ->
      {:ok, count} = Store.count_clients()
      threshold = length(Node.list()) - 1
      if threshold > 0 do
        counts =
          run_clustered fn ->
            {:ok, count} = Store.count_clients()
            count
          end

        average =
          counts
          |> Map.drop([@fake_local_node])
          |> Map.values
          |> Enum.sum
          |> :erlang./(threshold)

        goal = threshold / 2
        if count > average + goal do
          to_disconnect = Kernel.trunc count - (average + goal + 1)
          if to_disconnect > 0 do
            Logger.info "Disconnecting #{to_disconnect} sockets to load balance!"
            {status, result} = Store.get_clients to_disconnect
            case status do
              :ok ->
                for client <- result do
                  payload = Payload.close_with_payload(:goodbye, %{"reason" => "load balancing"})
                  send client.socket_pid, payload
                end

              :error ->
                Logger.error "Couldn't get sockets to load-balance away: #{result}"
            end
          end
        end
      end
    end
  end

  defp update_raft_state(state) do
    needs_raft_reactivation = !state[:rafted?] or state[:last_nodes] != Node.list()

    if needs_raft_reactivation do
      Logger.info "[CLUSTER] (Re)activating Raft zones"
      RaftFleet.activate Config.raft_zone()
    end

    if needs_raft_reactivation and not state[:rafted?] do
      Logger.info "[CLUSTER] Not currently rafted, attempting to activate consensus groups!"
      # Replicate consensus groups
      RaftFleet.consensus_groups()
      |> Enum.each(fn {group, _replica_count} ->
        case Atom.to_string(group) do
          "singyeong-queue:" <> queue_name ->
            Logger.debug "[CLUSTER] Joining queue consensus group: #{group}"
            Singyeong.Queue.create! queue_name

          _ ->
            Logger.warn "[CLUSTER] Asked to join consensus group #{group} but I don't know how!"
        end
      end)

      Logger.info "[CLUSTER] Raft activated!"
      %{state | rafted?: true, last_nodes: Node.list()}
    else
      %{state | rafted?: true, last_nodes: Node.list()}
    end
  end

  # CLUSTER-WIDE FUNCTIONS #

  @doc """
  Run a metadata query across the entire cluster, and return a mapping of nodes
  to matching client ids.
  """
  # TODO: Remove broadcast param
  def query(query, _broadcast \\ false) do
    run_clustered fn ->
      Singyeong.Store.query query
    end
  end

  @doc """
  Run the specified function across the entire cluster. Returns a mapping of
  nodes to results.
  """
  @spec run_clustered(function()) :: %{required(:fake_local_node | atom()) => term()}
  def run_clustered(func) do
    # Wrap the local function into an "awaitable" fn
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
      Utils.fast_list_concat acc, [task]
    end)
    |> Enum.map(&Task.await/1)
    |> Enum.reduce(%{}, fn(res, acc) ->
      # We should never have same-named nodes so it's nbd
      {node, task_result} = res
      acc |> Map.put(node, task_result)
    end)
  end

  # CLUSTERING HELPERS #

  @spec fake_local_node :: atom()
  def fake_local_node, do: @fake_local_node
end
