defmodule Singyeong.Gateway.Dispatch do
  @moduledoc """
  The dispatcher takes in events from clients and processes them in whatever
  manner is needed. This module ties together metadata querying, clustering,
  packet sending / receiving, and "exposes" them all in a way that incoming and
  outgoing messages can take reasonably use.
  """

  alias Singyeong.{Cluster, MessageDispatcher, PluginManager, Queue, Utils}
  alias Singyeong.Gateway.Payload
  alias Singyeong.Gateway.Payload.{QueueConfirm, QueuedMessage}
  alias Singyeong.Metadata.{Query, UpdateQueue}
  alias Singyeong.Store
  require Logger

  # TODO: Config option for this
  @max_send_tries 3
  # TODO: Config option for this too
  @retry_backoff_ms 1_000

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
        app = socket.assigns[:app_id]
        client = socket.assigns[:client_id]
        pid =
          app
          |> UpdateQueue.name(client)
          |> Process.whereis

        send pid, {:queue, client, metadata}
        # TODO: ACK metadata updates
        {:ok, []}

      {:error, errors} ->
        {:error, Payload.close_with_error("invalid metadata", errors)}
    end
  end

  def handle_dispatch(_, %Payload{t: "QUERY_NODES", d: data}) do
    {:ok, Payload.create_payload(:dispatch, "QUERY_NODES", %{"nodes" => Query.run_query(data, true)})}
  end

  def handle_dispatch(_, %Payload{t: "QUEUE", d: %{
    "nonce" => nonce,
    "queue" => queue_name,
    "target" => target,
    "payload" => payload
  }}) do
    Logger.debug "[DISPATCH] Queuing to #{queue_name}"
    :ok = Queue.create! queue_name
    queued_message =
      %QueuedMessage {
        id: UUID.uuid4(),
        target: target,
        queue: queue_name,
        nonce: nonce,
        payload: payload,
      }

    queue_name |> Queue.push(queued_message)
    {:ok, Payload.create_payload(:dispatch, "QUEUE_CONFIRM", %QueueConfirm{queue: queue_name})}
  end

  def handle_dispatch(socket, %Payload{t: "QUEUE_REQUEST", d: %{"queue" => queue_name}}) do
    :ok = Queue.create! queue_name
    {:ok, empty?} = Queue.is_empty? queue_name
    unless empty? do
      Logger.debug "[DISPATCH] Requesting pop from queue #{queue_name}"
      {:ok, %QueuedMessage{nonce: nonce, target: target, payload: payload}} = Queue.peek queue_name
      # TODO: Actually pop from the god damn queue you absolute fucking moron
      dispatch =
        %Payload.Dispatch{
          target: target,
          nonce: nonce,
          payload: payload,
        }
      matches = Cluster.query target
      send_with_retry socket, matches, dispatch, false
    else
      Logger.debug "[DISPATCH] Queue empty!"
    end
    {:ok, []}
  end

  def handle_dispatch(socket, %Payload{t: "SEND", d: data}) do
    send_to_clients socket, data, false
    {:ok, []}
  end

  def handle_dispatch(socket, %Payload{t: "BROADCAST", d: data}) do
    send_to_clients socket, data, true
    {:ok, []}
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
    # Query returns {app_id, [client_id]}
    # Clustering it returns a %{node => {app_id, [client_id]}}
    query_res
    |> Enum.map(fn
      {node, {_app, []}} ->
        {node, []}

      {node, {_app, clients}} ->
        {node, clients}
    end)
  end

  defp send_to_clients(socket, %Payload.Dispatch{} = data, broadcast?) do
    possible_clients =
      data.target
      |> Cluster.query(broadcast?)
      |> get_possible_clients

    send_with_retry socket, possible_clients, data, broadcast?
  end

  defp send_with_retry(socket, clients, %Payload.Dispatch{} = payload, broadcast?, tries \\ 0) do
    fake_local_node = Cluster.fake_local_node()
    empty? = Enum.empty? clients
    cond do
      not empty? and broadcast? ->
        # If we have clients, and we're broadcasting, ...
        for {node, clients} <- clients do
          send_fn = fn ->
            MessageDispatcher.send_dispatch clients, "BROADCAST", payload.nonce, payload.payload
          end

          case node do
            ^fake_local_node ->
              Task.Supervisor.async Singyeong.TaskSupervisor, send_fn

            _ ->
              Task.Supervisor.async {Singyeong.TaskSupervisor, node}, send_fn
          end
        end

      not empty? and not broadcast? ->
        # If we have clients, and we're not broadcasting, ...
        # Pick random node
        {node, clients} = Enum.random clients
        # Pick a random client from that node's targets
        target_client = [Enum.random(clients)]
        send_fn = fn ->
          MessageDispatcher.send_dispatch target_client, "SEND", payload.nonce, payload.payload
        end
        case node do
          ^fake_local_node ->
            Task.Supervisor.async Singyeong.TaskSupervisor, send_fn

          _ ->
            Task.Supervisor.async {Singyeong.TaskSupervisor, node}, send_fn
        end

      empty? and not payload.target.droppable? and tries >= @max_send_tries ->
        # If there's no matches, and it's not droppable, ...
        failure =
          Payload.create_payload :invalid, %{
            "error" => "no nodes match query for query #{inspect payload.target, pretty: true}",
            "d" => %{
              "nonce" => payload.nonce
            }
          }

        send socket.transport_pid, failure

      empty? and not payload.target.droppable? and tries < @max_send_tries ->
        # If there's no matches, and it's not droppable, and we HAVEN'T run out of tries yet, ...
        spawn fn ->
          Process.sleep @retry_backoff_ms
          send_with_retry socket, clients, payload, broadcast?, tries + 1
        end

      empty? and payload.target.droppable? ->
        # If there's no matches, and it's droppable, just silently drop it.
        nil
    end
  end
end
