defmodule Singyeong.Queue.Machine do
  @moduledoc """
  The Raft state machine for queues. This state machine tracks:
  - The current size / elements of the queue
  - The messages that clients have requested but not yet acked
  - The clients awaiting a new message
  """

  use TypedStruct
  alias Singyeong.Queue.Machine.State
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
    %State{
      queue: :queue.new(),
      length: 0,
      unacked_messages: %{},
      pending_clients: :queue.new(),
    }
  end

  def command({queue, len}, {:push, value}) do
    new_queue = :queue.in value, queue
    {:ok, {new_queue, len + 1}}
  end

  def command({queue, len} = state, :pop) do
    if len == 0 do
      {nil, state}
    else
      {{:value, value}, new_queue} = :queue.out queue
      {value, {new_queue, len - 1}}
    end
  end

  def query({queue, _}, :peek) do
    case :queue.peek(queue) do
      {:value, value} ->
        value

      :empty ->
        nil
    end
  end

  def query({_, len}, :length) do
    len
  end
end
