defmodule Singyeong.Gateway.Dispatch do
  @moduledoc """
  The dispatcher takes in events from clients and processes them in whatever
  manner is needed. This module ties together metadata querying, clustering,
  packet sending / receiving, and "exposes" them all in a way that incoming and
  outgoing messages can take reasonably use.
  """

  alias Singyeong.{Cluster, MessageDispatcher, PluginManager, Utils}
  alias Singyeong.Gateway.Payload
  alias Singyeong.Metadata.{Query, UpdateQueue}
  alias Singyeong.MnesiaStore, as: Store
  require Logger

  # TODO: Config option for this
  @max_send_tries 3
  # TODO: Config option for this too
  @retry_backoff_ms 1_000

  ## DISPATCH EVENTS ##

  def can_dispatch?(socket, event) do
    if socket.assigns[:restricted] do
      case event do
        "UPDATE_METADATA" ->
          true
        _ ->
          false
      end
    else
      true
    end
  end

  # Note: Dispatch handlers will return a list of response frames

  @spec handle_dispatch(Phoenix.Socket.t(), Payload.t())
    :: {:error, {:close, {:text, Payload.t()}}} | {:ok, [{:text, Payload.t()}]}
  def handle_dispatch(socket, %Payload{t: "UPDATE_METADATA", d: data} = _payload) do
    {status, res} = Store.validate_metadata data
    case status do
      :ok ->
        app_id = socket.assigns[:app_id]
        client_id = socket.assigns[:client_id]
        # Store.update_metadata socket.assigns[:app_id], socket.assigns[:client_id], res
        queue_worker = UpdateQueue.name app_id, client_id
        pid = Process.whereis queue_worker
        send pid, {:queue, app_id, client_id, res}
        {:ok, []}
      :error ->
        {:error, Payload.close_with_payload(:invalid, %{"error" => "couldn't validate metadata"})}
    end
  catch
    # Ideally we won't reach this case, but clients can't be trusted :<
    e ->
      formatted =
        Exception.format(:error, e, __STACKTRACE__)
      Logger.error "[DISPATCH] Encountered error handling metadata update:\n#{formatted}"
      {:error, Payload.close_with_payload(:invalid, %{"error" => "invalid metadata"})}
  end

  def handle_dispatch(_socket, %Payload{t: "QUERY_NODES", d: data} = _payload) do
    {:ok, Payload.create_payload(:dispatch, %{"nodes" => Query.run_query(data)})}
  end

  def handle_dispatch(socket, %Payload{t: "SEND", d: data} = _payload) do
    send_to_clients socket, data, 0, false
    {:ok, []}
  end

  def handle_dispatch(socket, %Payload{t: "BROADCAST", d: data} = _payload) do
    send_to_clients socket, data, 0
    {:ok, []}
  end

  def handle_dispatch(_socket, %Payload{t: t, d: data} = payload) do
    plugins = PluginManager.plugins_for_event t
    case plugins do
      [] ->
        {:error, Payload.close_with_payload(:invalid, %{"error" => "invalid dispatch payload: #{inspect payload, pretty: true}"})}

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

            error_payload =
              %{
                message: "Error processing plugin event #{t}",
                reason: reason,
                undo_errors: Enum.map(undo_errors, fn {:error, msg} -> msg end)
              }

            {:error, Payload.close_with_payload(:invalid, error_payload)}
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

  defp send_to_clients(socket, data, tries, broadcast \\ true) do
    %{"target" => target, "payload" => payload} = data
    targets = Cluster.query target
    valid_targets =
      targets
      |> Enum.filter(fn({_, {_, res}}) ->
        res != []
      end)
      |> Enum.into(%{})
    # Basically just flattening a list of lists
    matched_client_ids =
      valid_targets
      |> Map.values
      |> Enum.map(fn({_, res}) -> res end)
      |> Enum.concat

    unless Enum.empty?(matched_client_ids) do
      fake_local_node = Cluster.fake_local_node()
      out = %{
        "payload" => payload,
        "nonce" => data["nonce"]
      }

      if broadcast do
        for {node, {target_application, clients}} <- valid_targets do
          Logger.debug "Broadcasting message to #{target_application}:#{inspect clients} on node #{node}"
          send_fn = fn ->
            MessageDispatcher.send_dispatch target_application, clients, "BROADCAST", out
          end

          case node do
            ^fake_local_node ->
              Task.Supervisor.async Singyeong.TaskSupervisor, send_fn
            _ ->
              Task.Supervisor.async {Singyeong.TaskSupervisor, node}, send_fn
          end
        end
      else
        # Pick random node
        {node, {target_application, clients}} = Enum.random valid_targets
        # Pick a random client from that node's targets
        target_client = [Enum.random(clients)]
        Logger.debug "Sending message to #{target_application}:#{target_client} on node #{node}"
        send_fn = fn ->
          MessageDispatcher.send_dispatch target_application, target_client, "SEND", out
        end
        case node do
          ^fake_local_node ->
            Task.Supervisor.async Singyeong.TaskSupervisor, send_fn
          _ ->
            Task.Supervisor.async {Singyeong.TaskSupervisor, node}, send_fn
        end
      end
    else
      if tries == @max_send_tries do
        failure =
          Payload.create_payload(:invalid, %{
            "error" => "no nodes match query for query #{inspect target, pretty: true}",
            "d" => %{
              "nonce" => data["nonce"]
            }
          })
        send socket.transport_pid, failure
      else
        spawn fn ->
          Process.sleep @retry_backoff_ms
          send_to_clients socket, data, tries + 1, broadcast
        end
      end
    end
  end
end
