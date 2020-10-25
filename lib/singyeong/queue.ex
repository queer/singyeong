defmodule Singyeong.Queue do
  @moduledoc """
  An implementation of Raft-based, distributed, consistent message queues that
  still have all the routing capabilities of pubsub.
  """

  alias Singyeong.Queue.Machine
  require Logger

  # TODO: Make queue group size configurable
  @group_size 3

  @doc """
  Create a new queue with the given name as-needed.
  """
  @spec create!(String.t()) :: :ok | no_return()
  def create!(name) do
    name |> queue_name |> create_queue!
  end

  defp create_queue!(name_atom) do
    queue_debug name_atom, "Creating new queue..."
    config = RaftedValue.make_config Machine
    case RaftFleet.add_consensus_group(name_atom, @group_size, config) do
      :ok ->
        queue_debug name_atom, "Created new queue consensus group and awaiting leader."
        ^name_atom = await_leader name_atom, @group_size
        queue_debug name_atom, "Done!"
        :ok

      {:error, :already_added} ->
        # If it's already started, then we don't need to do anything
        ^name_atom = await_leader name_atom, @group_size
        queue_debug name_atom, "Queue exists, doing nothing!"
        :ok

      {:error, :no_leader} ->
        queue_debug name_atom, "No leader, awaiting..."
        ^name_atom = await_leader name_atom, @group_size
        queue_debug name_atom, "Leader acquired!"
        :ok

      # {:error, :cleanup_ongoing} ->
        # TODO: ??????

      err ->
        raise "Unknown queue pid start result: #{inspect err}"
    end
  end

  defp await_leader(queue, member_count) do
    if has_leader?(queue, member_count) do
      queue
    else
      :timer.sleep 50
      await_leader queue, member_count
    end
  end

  defp has_leader?(queue, member_count) do
    case RaftFleet.whereis_leader(queue) do
      pid when is_pid(pid) ->
        %{leader: leader, members: members, state_name: state} = RaftedValue.status pid
        queue_debug queue, "Awaiting master, leader=#{inspect leader}, members=#{inspect members, pretty: true}, expected_count=#{member_count}"
        leader != nil and length(members) <= member_count and state == :leader

      nil ->
        false
    end
  end

  @spec queue_name(String.t()) :: atom()
  def queue_name(name), do: :"singyeong-queue:#{name}"

  # We don't await_leader on these methods because it turns out to be
  # PROHIBITIVELY expensive!

  defp command(queue, cmd) do
    # group, command, timeout \\ 500, retry_count \\ 3, retry_interval \\ 1_000, call_module \\ :gen_statem
    RaftFleet.command queue, cmd, 5_000, 5, 100
  end

  defp query(queue, cmd) do
    # group, command, timeout \\ 500, retry_count \\ 3, retry_interval \\ 1_000, call_module \\ :gen_statem
    RaftFleet.query queue, cmd, 5_000, 5, 100
  end

  @spec push(String.t(), map()) :: term()
  def push(queue, payload) do
    queue
    |> queue_name
    |> queue_debug("Pushing new payload...")
    |> command({:push, payload})
  end

  @spec pop(String.t()) :: term()
  def pop(queue) do
    queue
    |> queue_name
    |> queue_debug("Popping new payload...")
    |> command(:pop)
  end

  @spec add_client(String.t(), {Store.app_id(), Store.client_id()}) :: term()
  def add_client(queue, client) do
    queue
    |> queue_name
    |> queue_debug("Appending new client: #{inspect client}...")
    |> command({:add_client, client})
  end

  @spec remove_client(String.t(), {Store.app_id(), Store.client_id()}) :: term()
  def remove_client(queue, client) do
    queue
    |> queue_name
    |> queue_debug("Removing client: #{inspect client}...")
    |> command({:remove_client, client})
  end

  @spec peek(String.t()) :: term()
  def peek(queue) do
    queue
    |> queue_name
    |> queue_debug("Peeking...")
    |> query(:peek)
  end

  @spec len(String.t()) :: term()
  def len(queue) do
    queue
    |> queue_name
    |> queue_debug("Detecting queue length...")
    |> query(:length)
  end

  def flush(queue) do
    queue
    |> queue_name
    |> queue_debug("Flushing...")
    |> query(:flush)
  end

  def dump(queue) do
    queue
    |> queue_name
    |> queue_debug("Dumping...")
    |> query(:dump)
  end

  @spec is_empty?(String.t()) :: {:ok, boolean()} | {:error, :no_leader}
  def is_empty?(queue) do
    len = len queue
    case len do
      {:ok, l} ->
        Logger.debug "[QUEUE] [#{queue_name queue}] Queue empty? #{l == 0} | #{inspect l, pretty: true}"
        {:ok, l == 0}

      err ->
        err
    end
  end

  defp queue_debug(queue_name, msg) do
    Logger.debug "[QUEUE] [#{queue_name}] #{msg}"
    queue_name
  end
end
