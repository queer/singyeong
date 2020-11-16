defmodule Singyeong.Queue do
  @moduledoc """
  An implementation of Raft-based, distributed, consistent message queues that
  still have all the routing capabilities of pubsub.
  """

  alias Singyeong.Config
  alias Singyeong.Gateway.Payload.QueuedMessage
  alias Singyeong.Queue.{
    Gc,
    Machine,
  }
  alias Singyeong.Utils
  require Logger

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
    case RaftFleet.add_consensus_group(name_atom, Config.queue_group_size(), config) do
      :ok ->
        queue_debug name_atom, "Created new queue consensus group and awaiting leader."
        ^name_atom = await_leader name_atom, Config.queue_group_size()
        queue_debug name_atom, "Done!"
        :ok

      {:error, :already_added} ->
        # If it's already started, then we don't need to do anything
        ^name_atom = await_leader name_atom, Config.queue_group_size()
        queue_debug name_atom, "Queue exists, doing nothing!"
        :ok

      {:error, :no_leader} ->
        queue_debug name_atom, "No leader, awaiting..."
        ^name_atom = await_leader name_atom, Config.queue_group_size()
        queue_debug name_atom, "Leader acquired!"
        :ok

      # {:error, :cleanup_ongoing} ->
        # :ok

      err ->
        raise "Unknown queue pid start result: #{inspect err}"
    end
    command name_atom, {:name, name_atom}
    # FIXME: This should be linked to the relevant Raft consensus group so that
    #        this dies when that does, but how?
    DynamicSupervisor.start_child Singyeong.QueueGcSupervisor,
      {Gc, [name: queue_readable_name(name_atom)]}

    :ok
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
  def queue_name(name), do: :"singyeong:queue:#{name}"

  @spec queue_readable_name(atom()) :: String.t()
  def queue_readable_name(name), do: name |> Atom.to_string |> String.replace("singyeong:queue:", "", global: false)

  # We don't await_leader on these functions because it turns out to be
  # PROHIBITIVELY expensive!

  defp command(queue, cmd) do
    # group, command, timeout \\ 500, retry_count \\ 3, retry_interval \\ 1_000, call_module \\ :gen_statem
    queue
    |> RaftFleet.command(cmd, 5_000, 5, 100)
    |> unwrap_command
  end

  defp query(queue, cmd) do
    # group, command, timeout \\ 500, retry_count \\ 3, retry_interval \\ 1_000, call_module \\ :gen_statem
    queue
    |> RaftFleet.query(cmd, 5_000, 5, 100)
    |> unwrap_command
  end

  @spec push(String.t(), map()) :: term()
  def push(queue, payload) do
    queue
    |> queue_name
    |> queue_debug("Pushing new payload...")
    |> command({:push, payload})
  end

  @spec pop(String.t()) :: {:ok, :ok}
                           | {:error, :empty_queue}
                           | {:error, :no_matches}
                           | {:error, :dlq}
                           | {:error, :no_pending_clients}
                           | {:error, :no_leader}
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

  @spec check_acks_and_dlq(String.t()) :: term()
  def check_acks_and_dlq(queue) do
    queue
    |> queue_name
    |> queue_debug("Processing ACKs and DLQ...")
    |> command({:check_acks_and_dlq, Utils.now()})
  end

  @spec add_dlq(String.t(), [Machine.DeadLetter.t()]) :: :ok
  def add_dlq(queue, msg) do
    queue
    |> queue_name
    |> queue_debug("Appending new message to DLQ...")
    |> command({:add_dlq, msg, Utils.now()})
  end

  @spec add_unacked(String.t(), {String.t(), QueuedMessage.t(), non_neg_integer()}) :: :ok
  def add_unacked(queue, {id, %QueuedMessage{}} = data) do
    queue
    |> queue_name
    |> queue_debug("Marking #{id} as unacked")
    |> command({:add_unacked, data, Utils.now()})
  end

  @spec ack_message(String.t(), String.t()) :: :ok
  def ack_message(queue, id) do
    queue
    |> queue_name
    |> queue_debug("Acking #{id}")
    |> command({:ack, id})
  end

  @spec flush(String.t()) :: term()
  def flush(queue) do
    queue
    |> queue_name
    |> queue_debug("Flushing...")
    |> command(:flush)
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

  @spec dump(String.t()) :: term()
  def dump(queue) do
    queue
    |> queue_name
    |> queue_debug("Dumping...")
    |> query(:dump)
  end

  @spec dump_full_state(String.t()) :: term()
  def dump_full_state(queue) do
    queue
    |> queue_name
    |> queue_debug("Dumping full state...")
    |> query(:dump_full_state)
  end

  @spec can_dispatch?(String.t()) :: {:ok, boolean()}
                                    | {:error, :empty_queue}
                                    | {:error, :no_pending_clients}
  def can_dispatch?(queue) do
    queue
    |> queue_name
    |> queue_debug("Checking for dispatchability...")
    |> query(:can_dispatch?)
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

  defp unwrap_command(res) do
    case res do
      {:ok, :ok} ->
        :ok

      {:ok, {:error, _} = err} ->
        err

      {:ok, {:ok, _} = out} ->
        out

      {:ok, _} = out ->
        out

      {:error, _} = err ->
        err
    end
  end
end
