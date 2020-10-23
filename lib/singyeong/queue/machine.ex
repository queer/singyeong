defmodule Singyeong.Queue.Machine do
  @moduledoc """
  The Raft state machine for queues. This state machine tracks:
  - The current size / elements of the queue
  - The messages that clients have requested but not yet acked
  - The clients awaiting a new message
  """

  use TypedStruct
  alias Singyeong.Queue.Machine.State
  alias Singyeong.Utils
  require Logger

  @behaviour RaftedValue.Data

  @type pending_client() :: {String.t(), String.t()}

  typedstruct module: State, enforce: true do
    field :queue, term()
    field :length, non_neg_integer()
    field :unacked_messages, map()
    field :pending_clients, term()
  end

  def new do
    base_state()
  end

  def command(state, {:push, value}) do
    new_queue = :queue.in value, state.queue
    {:ok, %{state | queue: new_queue, length: state.length + 1}}
  end

  def command(state, :pop) do
    if state.length == 0 do
      {nil, state}
    else
      # We don't check for a valid client in this function because this will
      # end up chewing up Raft command time w/ RPC etc. Instead, we peek the
      # next message, query, then attempt to pop the next message if we have a
      # possible match
      # TODO: This is a racy solution -- what do?
      {{:value, value}, new_queue} = :queue.out state.queue
      {value, %{state | queue: new_queue, length: state.length - 1}}
    end
  end

  def command(state, {:add_client, client}) do
    new_clients = Utils.fast_list_concat state.pending_clients, client
    {:ok, %{state | pending_clients: new_clients}}
  end

  def command(_, :flush) do
    {:ok, base_state()}
  end

  def query(%State{queue: queue}, :peek) do
    case :queue.peek(queue) do
      {:value, value} ->
        value

      :empty ->
        nil
    end
  end

  def query(%State{length: len}, :length) do
    len
  end

  defp base_state, do: %__MODULE__.State{
    queue: :queue.new(),
    length: 0,
    unacked_messages: %{},
    pending_clients: [],
  }
end
