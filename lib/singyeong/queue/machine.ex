defmodule Singyeong.Queue.Machine do
  @moduledoc """
  The Raft state machine for queues. This state machine tracks:
  - The current size / elements of the queue
  - The messages that clients have requested but not yet acked
  - The clients awaiting a new message
  - The dead-letter queue
  """

  use TypedStruct
  alias Singyeong.Config
  alias Singyeong.Gateway.Payload.QueuedMessage
  alias Singyeong.Queue
  alias Singyeong.Queue.Machine.{AwaitingAck, DeadLetter, State}
  alias Singyeong.Store
  alias Singyeong.Utils
  require Logger

  @behaviour RaftedValue.Data

  typedstruct module: State, enforce: true do
    @moduledoc """
    The Raft state machine's state.
    """
    @type pending_client() :: {Store.app_id(), Store.client_id()}
    field :queue, term()
    field :length, non_neg_integer()
    field :unacked_messages, %{optional(binary()) => AwaitingAck.t()}
    field :pending_clients, [pending_client()]
    field :dlq, [DeadLetter.t()]
    field :name, String.t()
  end

  typedstruct module: AwaitingAck, enforce: true do
    @moduledoc """
    A message awaiting an ACK from the client working on it. If the message is
    not ACKed within the configured waiting period, it is moved to the DLQ,
    from where it will be eventually requeued.
    """
    field :message, QueuedMessage.t()
    field :awaiting_since, non_neg_integer()
  end

  typedstruct module: DeadLetter, enforce: true do
    @moduledoc """
    A message that could not be delivered and is thus "dead." Dead messages are
    moved to the DLQ, from which they will be re-queued according to how the
    configured waiting period.
    """
    field :message, QueuedMessage.t()
    field :dead_since, non_neg_integer()
  end

  @impl RaftedValue.Data
  def new do
    base_state()
  end

  @impl RaftedValue.Data
  def command(%State{queue: queue, length: length} = state, {:push, value}) do
    new_queue = :queue.in value, queue
    {:ok, %{state | queue: new_queue, length: length + 1}}
  end

  @impl RaftedValue.Data
  def command(%State{
    queue: queue,
    length: length,
  } = state, :pop) do
    {{:value, %QueuedMessage{} = message}, new_queue} = :queue.out queue
    {{:ok, message}, %{state | queue: new_queue, length: length - 1}}
  end

  @impl RaftedValue.Data
  def command(%State{pending_clients: clients} = state, {:add_client, client}) do
    new_clients = Utils.fast_list_concat clients, client
    {:ok, %{state | pending_clients: new_clients}}
  end

  @impl RaftedValue.Data
  def command(%State{pending_clients: clients} = state, {:remove_client, client}) do
    new_clients = Enum.filter clients, fn c -> c != client end
    {:ok, %{state | pending_clients: new_clients}}
  end

  @impl RaftedValue.Data
  def command(_, :flush) do
    {:ok, base_state()}
  end

  @impl RaftedValue.Data
  def command(state, {:name, name_atom}) do
    {:ok, %{state | name: Queue.queue_readable_name(name_atom)}}
  end

  @impl RaftedValue.Data
  def command(%State{dlq: dlq} = state, {:add_dlq, %QueuedMessage{} = msg, now}) do
    dead =
      %DeadLetter{
        message: msg,
        dead_since: now,
      }

    {:ok, %{state | dlq: Utils.fast_list_concat(dlq, dead)}}
  end

  def command(%State{unacked_messages: unacked_messages} = state, {:add_unacked, {id, %QueuedMessage{} = msg}, now}) do
    unacked =
      %AwaitingAck{
        message: msg,
        awaiting_since: now,
      }

    {:ok, %{state | unacked_messages: Map.put(unacked_messages, id, unacked)}}
  end

  @impl RaftedValue.Data
  def command(%State{
    queue: queue,
    dlq: dlq,
    unacked_messages: unacked_messages,
  } = state, {:check_acks_and_dlq, now}) do
    {still_unacked, dead_by_ack} =
      Enum.reduce unacked_messages, {%{}, []}, fn {id, %AwaitingAck{
            message: %QueuedMessage{id: id} = msg,
            awaiting_since: since
          } = awaiting}, {still_unacked, dead} ->
        if now - since >= Config.queue_ack_timeout() do
          Logger.debug "[QUEUE] [MACHINE] [#{state.name}] #{id}: unacked -> dead"
          {still_unacked, Utils.fast_list_concat(dead, %DeadLetter{dead_since: now, message: msg})}
        else
          Logger.debug "[QUEUE] [MACHINE] [#{state.name}] #{id}: unacked -> still_unacked"
          {Map.put(still_unacked, id, awaiting), dead}
        end
      end

    {still_dead, undead} =
      Enum.reduce dlq, {[], []}, fn %DeadLetter{
            message: %QueuedMessage{id: id} = msg,
            dead_since: since,
          } = dead, {still_dead, undead} ->
        if now - since >= Config.queue_dlq_time() do
          Logger.debug "[QUEUE] [MACHINE] [#{state.name}] #{id}: dead -> undead"
          {still_dead, Utils.fast_list_concat(undead, msg)}
        else
          Logger.debug "[QUEUE] [MACHINE] [#{state.name}] #{id}: dead -> still_dead"
          {Utils.fast_list_concat(still_dead, dead), undead}
        end
      end

    new_dlq = Utils.fast_list_concat still_dead, dead_by_ack
    new_queue =
      Enum.reduce undead, queue, fn undead_msg, acc ->
        :queue.in undead_msg, acc
      end

    {:ok, %{state | unacked_messages: still_unacked, dlq: new_dlq, queue: new_queue}}
  end

  @impl RaftedValue.Data
  def command(%State{unacked_messages: unacked} = state, {:ack, id}) do
    {:ok, %{state | unacked_messages: Map.delete(unacked, id)}}
  end

  @impl RaftedValue.Data
  def query(%State{queue: queue, pending_clients: pending}, :peek) do
    case :queue.peek(queue) do
      {:value, value} ->
        {value, pending}

      :empty ->
        nil
    end
  end

  @impl RaftedValue.Data
  def query(%State{length: len}, :length) do
    len
  end

  @impl RaftedValue.Data
  def query(%State{queue: queue}, :dump) do
    queue
  end

  @impl RaftedValue.Data
  def query(state, :dump_full_state) do
    state
  end

  @impl RaftedValue.Data
  def query(%{length: length, pending_clients: pending_clients}, :can_dispatch?) do
    cond do
      # See: https://github.com/rrrene/credo/issues/824
      # credo:disable-for-next-line
      length == 0 ->
        {:error, :empty_queue}

      pending_clients == [] ->
        {:error, :no_pending_clients}

      true ->
        {:ok, true}
    end
  end

  defp base_state, do: %State{
    queue: :queue.new(),
    length: 0,
    unacked_messages: %{},
    pending_clients: [],
    dlq: [],
    name: "<unknown>",
  }
end
