defmodule Singyeong.Gateway.Dispatch do
  @moduledoc """
  The dispatcher takes in events from clients and processes them in whatever
  manner is needed. This module ties together metadata querying, clustering,
  packet sending / receiving, and "exposes" them all in a way that incoming and
  outgoing messages can take reasonably use.
  """

  alias Singyeong.{Cluster, MessageDispatcher, PluginManager, Queue, Utils}
  alias Singyeong.Gateway.{Payload, Pipeline}
  alias Singyeong.Gateway.Payload.{
    QueueAck,
    QueueConfirm,
    QueueDispatch,
    QueuedMessage,
    QueueInsert,
    QueueRequest,
  }
  alias Singyeong.Metadata.{Query, UpdateQueue}
  alias Singyeong.Store
  require Logger

  ## DISPATCH EVENTS ##

  def can_dispatch?(socket, event) do
    cond do
      socket.assigns[:restricted] and event == "UPDATE_METADATA" -> true
      socket.assigns[:restricted] -> false
      true -> true
    end
  end

  @spec handle_dispatch(Phoenix.Socket.t(), Payload.t())
    :: {:error, {:close, {:text, Payload.t()}}}
       | {:ok, []
               | {:text, Payload.t()}
               | [{:text, Payload.t()}]}
  def handle_dispatch(socket, %Payload{t: "UPDATE_METADATA", d: data}) do
    case Store.validate_metadata(data) do
      {:ok, {types, metadata}} ->
        app = socket.assigns.app_id
        client = socket.assigns.client_id
        pid =
          app
          |> UpdateQueue.name(client)
          |> Process.whereis

        send pid, {:queue, {app, client}, {types, metadata}}
        # TODO: ACK metadata updates
        {:ok, []}

      {:error, errors} ->
        {:error, Payload.error("invalid metadata", errors)}
    end
  end

  def handle_dispatch(_, %Payload{t: "QUERY_NODES", d: data}) do
    {:ok, Payload.create_payload(:dispatch, "QUERY_NODES", %{"nodes" => Cluster.query(data)})}
  end

  def handle_dispatch(_, %Payload{t: "QUEUE", d: %QueueInsert{
    nonce: nonce,
    queue: queue_name,
    target: %Query{} = target,
    payload: payload,
  }}) do
    :ok = Queue.create! queue_name
    queued_message =
      %QueuedMessage{
        id: UUID.uuid4(),
        queue: queue_name,
        payload: payload,
        nonce: nonce,
        target: target,
      }

    :ok = Queue.push queue_name, queued_message
    attempt_queue_dispatch queue_name
    {:ok, Payload.create_payload(:dispatch, "QUEUE_CONFIRM", %QueueConfirm{queue: queue_name})}
  end

  def handle_dispatch(socket, %Payload{t: "QUEUE_REQUEST", d: %QueueRequest{queue: queue_name}}) do
    app_id = socket.assigns.app_id
    client_id = socket.assigns.client_id
    :ok = Queue.create! queue_name
    :ok = Queue.add_client queue_name, {app_id, client_id}
    {:ok, client} = Store.get_client app_id, client_id
    client = %{client | queues: Utils.fast_list_concat(client.queues, queue_name)}
    {:ok, _} = Store.update_client client
    attempt_queue_dispatch queue_name
    {:ok, []}
  end

  def handle_dispatch(socket, %Payload{t: "QUEUE_REQUEST_CANCEL", d: %QueueRequest{queue: queue_name}}) do
    app_id = socket.assigns.app_id
    client_id = socket.assigns.client_id
    :ok = Queue.create! queue_name
    :ok = Queue.remove_client queue_name, {app_id, client_id}
    {:ok, client} = Store.get_client app_id, client_id
    client = %{client | queues: Enum.reject(client.queues, &(&1 == Queue.queue_name(queue_name)))}
    {:ok, _} = Store.update_client client
    {:ok, []}
  end

  def handle_dispatch(_, %Payload{t: "QUEUE_ACK", d: %QueueAck{queue: queue_name, id: id}}) do
    :ok = Queue.create! queue_name
    :ok = Queue.ack_message queue_name, id
    {:ok, []}
  end

  def handle_dispatch(socket, %Payload{t: "SEND", d: data} = payload) do
    case send_to_clients(socket, data, false) do
      {:ok, _} ->
        {:ok, []}

      {:error, value} ->
        {:error, Payload.error(value, Payload.to_outgoing(payload))}
    end
  end

  def handle_dispatch(socket, %Payload{t: "BROADCAST", d: data} = payload) do
    case send_to_clients(socket, data, true) do
      {:ok, _} ->
        {:ok, []}

      {:error, value} ->
        {:error, Payload.error(value, Payload.to_outgoing(payload))}
    end
  end

  def handle_dispatch(_, %Payload{t: t, d: data} = payload) do
    plugins = PluginManager.plugins_for_event :custom_events, t
    case plugins do
      [] ->
        {:error, Payload.error("invalid dispatch payload", payload)}

      plugins when is_list(plugins) ->
        case Pipeline.run_pipeline(plugins, t, data, [], []) do
          {:ok, _frames} = res ->
            res

          :halted ->
            {:ok, []}

          {:error, reason, undo_states} ->
            undo_errors =
              undo_states
              # TODO: This should really just append undo states in reverse...
              |> Enum.reverse
              |> Pipeline.unwind_undo_stack(t)

            error_info =
              %{
                reason: reason,
                undo_errors: Enum.map(undo_errors, fn {:error, msg} -> msg end)
              }

            {:error, Payload.error("Error processing plugin event #{t}", error_info)}
        end
    end
  end

  defp get_possible_clients(clients) do
    client_count =
      clients
      |> Enum.flat_map(fn {_, clients} -> clients end)
      |> Enum.count

    {Map.to_list(clients), client_count}
  end

  def send_to_clients(socket, %Payload.Dispatch{} = data, broadcast?, type \\ nil) do
    # TODO: Relocate this type of code to MessageDispatcher?
    {possible_clients, client_count} =
      data.target
      |> Cluster.query
      |> get_possible_clients

    MessageDispatcher.send_message socket, possible_clients, client_count, data, broadcast?, type
  end

  defp attempt_queue_dispatch(queue_name) do
    case Queue.can_dispatch?(queue_name) do
      {:error, :empty_queue} ->
        :ok

      {:error, :no_pending_clients} ->
        :ok

      {:ok, true} ->
        attempt_queue_dispatch0 queue_name
    end
  end

  defp attempt_queue_dispatch0(queue_name) do
    {:ok, {%QueuedMessage{
      target: target,
    } = message, pending_clients}} = Queue.peek queue_name

    # Query the metadata store to find matching clients, and dispatch the
    # queued message to the client that's been waiting the longest. Due to
    # current limitations of the query engine, this queries all clients for
    # the pending application, then computes the intersection of that set of
    # clients with the set of pending clients, picking the first match,
    # ie hd(pending ∩ matches).
    # TODO: This query should only be run over pending clients
    target
    |> Cluster.query
    |> get_possible_clients
    # {matches, count}
    |> case do
      {_, 0} ->
        {:ok, next_message} = Queue.pop queue_name
        # No clients, DLQ it
        :ok = Queue.add_dlq queue_name, next_message

      {matches, count} when count > 0 ->
        {:ok, %QueuedMessage{payload: payload, id: id, nonce: nonce}} = Queue.pop queue_name
        next_client_id =
          pending_clients
          |> intersection(matches)
          |> case do
            [] ->
              nil

            [_ | _] = res ->
              hd res
          end

        if next_client_id != nil do
          {node, [next_client]} =
            matches
            |> Enum.filter(fn {_node, clients} ->
              Enum.any? clients, fn client ->
                next_client_id == {client.app_id, client.client_id}
              end
            end)
            |> hd

          outgoing_payload =
            %QueueDispatch{
              queue: queue_name,
              payload: payload,
              id: id,
            }

          :ok = Queue.remove_client queue_name, {next_client.app_id, next_client.client_id}

          # Queues can only send to a single client, so client_count=1
          MessageDispatcher.send_message nil, [{node, [next_client]}], 1, %Payload.Dispatch{
              target: target,
              nonce: nonce,
              payload: outgoing_payload
            }, false, "QUEUE"

          Queue.add_unacked queue_name, {id, message}
        end
    end
  end

  defp intersection(pending_clients, matches) do
    matches
    |> Enum.flat_map(fn {_node, clients} -> clients end)
    |> Enum.map(fn client -> {client.app_id, client.client_id} end)
    |> Enum.filter(&Enum.member?(pending_clients, &1))
  end
end
