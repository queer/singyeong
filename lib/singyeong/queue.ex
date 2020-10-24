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
    Logger.info "[QUEUE] [#{name_atom}] Creating new queue..."
    config = RaftedValue.make_config Machine
    case RaftFleet.add_consensus_group(name_atom, @group_size, config) do
      :ok ->
        Logger.info "[QUEUE] [#{name_atom}] Created new queue consensus group and awaiting leader."
        ^name_atom = await_leader name_atom, @group_size
        Logger.info "[QUEUE] [#{name_atom}] Done!"
        :ok

      {:error, :already_added} ->
        # If it's already started, then we don't need to do anything
        Logger.debug "[QUEUE] [#{name_atom}] Queue exists, doing nothing!"
        :ok

      {:error, :no_leader} ->
        Logger.debug "[QUEUE] [#{name_atom}] No leader, awaiting..."
        ^name_atom = await_leader name_atom, @group_size
        Logger.debug "[QUEUE] [#{name_atom}] Leader acquired!"
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
      :timer.sleep 100
      await_leader queue, member_count
    end
  end

  defp has_leader?(queue, member_count) do
    case RaftFleet.whereis_leader(queue) do
      pid when is_pid(pid) ->
        %{leader: leader, members: members} = RaftedValue.status pid
        Logger.debug "[QUEUE] [#{queue_name queue}] Awaiting master, leader=#{inspect leader}, members=#{inspect members, pretty: true}"
        leader != nil and length(members) <= member_count

      nil ->
        false
    end
  end

  @spec queue_name(String.t()) :: atom()
  def queue_name(name), do: :"singyeong-queue:#{name}"

  # We don't await_leader on these methods because it turns out to be
  # PROHIBITIVELY expensive!

  @spec push(String.t(), map()) :: term()
  def push(queue, payload) do
    Logger.debug "[QUEUE] [#{queue_name queue}] Pushing new payload..."
    queue
    |> queue_name
    |> RaftFleet.command({:push, payload}, 5_000)
  end

  @spec pop(String.t()) :: term()
  def pop(queue) do
    Logger.debug "[QUEUE] [#{queue_name queue}] Popping new payload..."
    queue
    |> queue_name
    |> RaftFleet.command(:pop, 5_000)
  end

  @spec peek(String.t()) :: term()
  def peek(queue) do
    queue
    |> queue_name
    |> RaftFleet.query(:peek, 5_000)
  end

  @spec len(String.t()) :: term()
  def len(queue) do
    Logger.debug "[QUEUE] [#{queue_name queue}] Detecting queue length..."
    queue
    |> queue_name
    |> RaftFleet.query(:length, 5_000)
  end

  def flush(queue) do
    Logger.debug "[QUEUE] [#{queue_name queue}] Flushing..."
    queue
    |> queue_name
    |> RaftFleet.query(:flush, 5_000)
  end

  def dump(queue) do
    Logger.debug "[QUEUE] [#{queue_name queue}] Dumping..."
    queue
    |> queue_name
    |> RaftFleet.query(:dump, 5_000)
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
end
