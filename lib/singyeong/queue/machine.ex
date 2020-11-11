defmodule Singyeong.Queue.Machine do
  @moduledoc """
  The Raft state machine for queues. This state machine tracks:
  - The current size / elements of the queue
  - The messages that clients have requested but not yet acked
  - The clients awaiting a new message
  """

  use TypedStruct
  alias Singyeong.Cluster
  alias Singyeong.Gateway.Payload
  alias Singyeong.Gateway.Payload.QueuedMessage
  alias Singyeong.MessageDispatcher
  alias Singyeong.Queue.Machine.State
  alias Singyeong.Store
  alias Singyeong.Utils
  require Logger

  @behaviour RaftedValue.Data

  typedstruct module: State, enforce: true do
    @type pending_client() :: {Store.app_id(), Store.client_id()}
    field :queue, term()
    field :length, non_neg_integer()
    field :unacked_messages, map()
    field :pending_clients, [pending_client()]
  end

  def new do
    base_state()
  end

  def command(state, {:push, value}) do
    new_queue = :queue.in value, state.queue
    {:ok, %{state | queue: new_queue, length: state.length + 1}}
  end

  def command(%State{queue: queue, length: length} = state, :pop) do
    if state.length == 0 do
      {nil, state}
    else
      # TODO: haha chewing up Raft time with RPC
      {:value, %QueuedMessage{target: target} = peek} = :queue.peek queue
      # TODO: This should only match on pending clients
      matches = target |> Cluster.query |> Singyeong.Gateway.Dispatch.get_possible_clients
      case matches do
        [] ->
          # TODO: DLQ
          {{:error, :no_matches}, state}

        [{node, client} | _] ->
          {{:value, %QueuedMessage{target: target, nonce: nonce, payload: payload}}, new_queue} = :queue.out queue
          # TODO: This should be correct number
          MessageDispatcher.send_with_retry nil, [{node, client}], -1, %Payload.Dispatch{target: target, nonce: nonce, payload: payload}, false
          {:ok, %{state | queue: new_queue, length: length - 1}}
      end
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

  def query(%State{queue: queue}, :dump) do
    queue
  end

  defp base_state, do: %__MODULE__.State{
    queue: :queue.new(),
    length: 0,
    unacked_messages: %{},
    pending_clients: [],
  }
end
