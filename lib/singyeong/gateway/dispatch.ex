defmodule Singyeong.Gateway.Dispatch do
  @moduledoc """
  The dispatcher takes in events from clients and processes them in whatever
  manner is needed. This module ties together metadata querying, clustering,
  packet sending / receiving, and "exposes" them all in a way that incoming and
  outgoing messages can take reasonably use.
  """

  alias Singyeong.{Cluster, MessageDispatcher, PluginManager, Queue, Utils}
  alias Singyeong.Gateway.Payload
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
      socket.assigns[:restricted] && event == "UPDATE_METADATA" ->
        true

      socket.assigns[:restricted] ->
        false

      true ->
        true
    end
  end

  @spec handle_dispatch(Phoenix.Socket.t(), Payload.t())
    :: {:error, {:close, {:text, Payload.t()}}}
       | {:ok, []
               | {:text, Payload.t()}
               | [{:text, Payload.t()}]}
  def handle_dispatch(socket, %Payload{t: "UPDATE_METADATA", d: data}) do
    case Store.validate_metadata(data) do
      {:ok, metadata} ->
        app = socket.assigns.app_id
        client = socket.assigns.client_id
        pid =
          app
          |> UpdateQueue.name(client)
          |> Process.whereis

        send pid, {:queue, {app, client}, metadata}
        # TODO: ACK metadata updates
        {:ok, []}

      {:error, errors} ->
        {:error, Payload.close_with_error("invalid metadata", errors)}
    end
  end

  def handle_dispatch(_, %Payload{t: "QUERY_NODES", d: data}) do
    {:ok, Payload.create_payload(:dispatch, "QUERY_NODES", %{"nodes" => Query.run_query(data, true)})}
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
        {:error, Payload.close_with_error("Unroutable payload: #{value}", payload)}
    end
  end

  def handle_dispatch(socket, %Payload{t: "BROADCAST", d: data} = payload) do
    case send_to_clients(socket, data, true) do
      {:ok, _} ->
        {:ok, []}

      {:error, value} ->
        {:error, Payload.close_with_error("Unroutable payload: #{value}", payload)}
    end
  end

  def handle_dispatch(_, %Payload{t: t, d: data} = payload) do
    plugins = PluginManager.plugins_for_event :custom_events, t
    case plugins do
      [] ->
        {:error, Payload.close_with_error("invalid dispatch payload", payload)}

      plugins when is_list(plugins) ->
        case run_pipeline(plugins, t, data, [], []) do
          {:ok, _frames} = res ->
            res

          :halted ->
            {:ok, []}

          {:error, reason, undo_states} ->
            undo_errors =
              undo_states
              # TODO: This should really just append undo states in reverse...
              |> Enum.reverse
              |> unwind_undo_stack(t)

            error_info =
              %{
                reason: reason,
                undo_errors: Enum.map(undo_errors, fn {:error, msg} -> msg end)
              }

            {:error, Payload.close_with_error("Error processing plugin event #{t}", error_info)}
        end
    end
  end

  @spec run_pipeline([atom()], binary(), any(), [Payload.t()], [any()]) ::
          {:ok, [Payload.t()]}
          | :halted
          | {:error, binary(), [{atom(), any()}]}
  # credo:disable-for-next-line
  defp run_pipeline([plugin | rest], event, data, frames, undo_states) do
    case plugin.handle_event(event, data) do
      {:next, plugin_frames, plugin_undo_state} when not is_nil(plugin_frames) and not is_nil(plugin_undo_state) ->
        out_frames = Utils.fast_list_concat frames, plugin_frames
        out_undo_states = Utils.fast_list_concat undo_states, {plugin, plugin_undo_state}
        run_pipeline rest, event, data, out_frames, out_undo_states

      {:next, plugin_frames, nil} when not is_nil(plugin_frames) ->
        out_frames = Utils.fast_list_concat frames, plugin_frames
        run_pipeline rest, event, data, out_frames, undo_states

      {:next, plugin_frames} when not is_nil(plugin_frames) ->
        out_frames = Utils.fast_list_concat frames, plugin_frames
        run_pipeline rest, event, data, out_frames, undo_states

      {:halt, _} ->
        # Halts do not return execution to the pipeline, nor do they return any
        # side-effects (read: frames) to the client.
        :halted

      :halt ->
        :halted

      {:error, reason} when is_binary(reason) ->
        {:error, reason, undo_states}

      {:error, reason, plugin_undo_state} when is_binary(reason) and not is_nil(plugin_undo_state) ->
        out_undo_states = Utils.fast_list_concat undo_states, {plugin, plugin_undo_state}
        {:error, reason, out_undo_states}

      {:error, reason, nil} when is_binary(reason) ->
        {:error, reason, undo_states}
    end
  end
  defp run_pipeline([], _, _, frames, _undo_states) do
    {:ok, frames}
  end

  defp unwind_undo_stack(undo_states, event) do
    undo_states
    |> Enum.filter(fn {_, state} -> state != nil end)
    |> Enum.map(fn undo_state -> undo(undo_state, event) end)
    # We only want the :error tuple results so that we can report them to the
    # client; successful undos don't need to be reported.
    |> Enum.filter(fn res -> res != :ok end)
  end
  defp undo({plugin, undo_state}, event) do
    # We don't just take a list of the undo states here, because really we do
    # not want to halt undo when one encounters an error; instead, we want to
    # continue the undo and then report all errors to the client.
    apply plugin, :undo, [event, undo_state]
  end

  defp get_possible_clients(query_res) do
    # Query returns {app_id, [client]}
    # Clustering it returns a %{node => {app_id, [client]}}
    # This converts it to a [{node, [{app_id, client}]}]
    clients =
      query_res
      |> Enum.map(fn
        {node, {_app, []}} ->
          {node, []}

        {node, {app, clients}} ->
          {node, Enum.map(clients, &{app, &1})}
      end)

    client_count =
      clients
      |> Enum.flat_map(fn {_, clients} -> clients end)
      |> Enum.count

    {clients, client_count}
  end

  defp send_to_clients(socket, %Payload.Dispatch{} = data, broadcast?) do
    {possible_clients, client_count} =
      data.target
      |> Cluster.query(broadcast?)
      |> get_possible_clients

    MessageDispatcher.send_with_retry socket, possible_clients, client_count, data, broadcast?
  end

  defp attempt_queue_dispatch(queue_name) do
    case Queue.can_dispatch?(queue_name) do
      {:error, :empty_queue} ->
        :ok

      {:error, :no_pending_clients} ->
        :ok

      {:ok, true} ->
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
          # {{:value, %QueuedMessage{} = message}, new_queue} = :queue.out queue
          # dlq = Utils.fast_list_concat dlq, %DeadLetter{message: message, dead_since: now}
          # {{:error, :dlq}, %{state | dlq: dlq, queue: new_queue}}
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
                Enum.any? clients, fn {app, client} ->
                  next_client_id == {app, client.client_id}
                end
              end)
              |> hd

            outgoing_payload =
              %QueueDispatch{
                queue: queue_name,
                payload: payload,
                id: id,
              }

            {app_id, %{client_id: client_id}} = next_client
            :ok = Queue.remove_client queue_name, {app_id, client_id}

            # Queues can only send to a single client, so client_count=1
            MessageDispatcher.send_with_retry nil, [{node, [next_client]}], 1, %Payload.Dispatch{
                target: target,
                nonce: nonce,
                payload: outgoing_payload
              }, false, "QUEUE"

            Queue.add_unacked queue_name, {id, message}
          end
      end
    end
  end

  defp intersection(pending_clients, matches) do
    matches
    |> Enum.flat_map(fn {_node, clients} -> clients end)
    |> Enum.map(fn {app_id, client} -> {app_id, client.client_id} end)
    |> Enum.filter(&Enum.member?(pending_clients, &1))
  end
end
