defmodule Singyeong.Queue do
  alias Singyeong.Cluster
  alias Singyeong.Queue.Machine
  require Logger

  @group_size 3

  @doc """
  Create a new queue with the given name as-needed.
  """
  @spec create!(String.t()) :: :ok | no_return()
  def create!(name) do
    queue = queue_name name
    if RaftFleet.whereis_leader(queue) do
      :ok
    else
      create_queue! queue
    end
  end

  defp create_queue!(name_atom) do
    Logger.info "[QUEUE] [#{name_atom}] Creating new queue..."
    config = RaftedValue.make_config Machine
    # TODO: Make queue group size configurable
    case RaftFleet.add_consensus_group(name_atom, @group_size, config) do
      :ok ->
        Logger.info "[QUEUE] [#{name_atom}] Created new queue consensus group and awaiting leader."
        me = Node.self()
        # TODO: This needs to ONLY run across nodes in the consensus group!
        Cluster.run_clustered fn ->
          if Node.self() != me do
            # Join other nodes to the consensus group
            Logger.info "[QUEUE] [#{name_atom}] #{inspect RaftFleet.active_nodes(), pretty: true}"
          end
        end
        ^name_atom = await_leader name_atom, @group_size
        Logger.info "[QUEUE] [#{name_atom}] Done!"
        :ok

      {:error, :already_added} ->
        Logger.debug "[QUEUE] [#{name_atom}] Queue started, awaiting leader..."
        ^name_atom = await_leader name_atom, @group_size
        # If it's already started, then we don't need to do anything
        :ok

      {:error, :no_leader} ->
        Logger.info "[QUEUE] [#{name_atom}] No leader, awaiting..."
        ^name_atom = await_leader name_atom, @group_size
        :ok

      # {:error, :cleanup_ongoing} ->
        # TODO: ??????

      err ->
        raise "Unknown queue pid start result: #{inspect err}"
    end
  end

  defp await_leader(queue, member_count) do
    me = self()
    ref = make_ref()
    spawn_link fn ->
      :timer.sleep 100
      send me, ref
    end
    receive do
      ^ref ->
        # Check if we have a leader. If we do, yay! If we don't, keep blocking.
        if has_leader?(queue, member_count) do
          # Logger.debug "[QUEUE] [#{queue}] Found leader: #{queue |> RaftFleet.whereis_leader |> inspect}"
          queue
        else
          await_leader queue, member_count
        end
    end
  end

  defp has_leader?(queue, member_count) do
    case RaftFleet.whereis_leader(queue) do
      pid when is_pid(pid) ->
        %{leader: leader, members: members} = RaftedValue.status pid
        # Logger.debug "[QUEUE] [#{queue}] Tentatively found leader: #{inspect pid}, nodes=#{Node.list() |> Kernel.length |> Kernel.+(1)}"
        # Logger.debug "[QUEUE] [#{queue}] Members:\n#{inspect members, pretty: true}\nZone:\n#{inspect RaftFleet.active_nodes(), pretty: true}"
        leader != nil and length(members) == member_count

      nil ->
        false
    end
  end

  @spec queue_name(String.t()) :: atom()
  def queue_name(name), do: :"singyeong-queue:#{name}"

  @spec push(String.t(), map()) :: term()
  def push(queue, payload) do
    queue
    |> queue_name
    |> await_leader(@group_size)
    |> RaftFleet.command({:push, payload}, 5_000)
  end

  @spec pop(String.t()) :: term()
  def pop(queue) do
    queue
    |> queue_name
    |> await_leader(@group_size)
    |> RaftFleet.command(:pop, 5_000)
  end

  @spec peek(String.t()) :: term()
  def peek(queue) do
    queue
    |> queue_name
    |> await_leader(@group_size)
    |> RaftFleet.query(:peek, 5_000)
  end

  @spec len(String.t()) :: term()
  def len(queue) do
    queue
    |> queue_name
    |> await_leader(@group_size)
    |> RaftFleet.query(:length, 5_000)
  end

  @spec is_empty?(String.t()) :: {:ok, boolean()} | {:error, :no_leader}
  def is_empty?(queue) do
    len = len queue
    Logger.debug "[QUEUE] [#{queue_name queue}] Found length: #{inspect len}"
    case len do
      {:ok, l} ->
        {:ok, l == 0}

      err ->
        err
    end
  end
end
