defmodule Singyeong.Gateway.Handler.DispatchEvent do
  use Singyeong.Gateway.Handler
  alias Singyeong.{PluginManager, Utils}
  alias Singyeong.Gateway.Dispatch

  def handle(socket, payload) do
    dispatch_type = payload.t
    if Dispatch.can_dispatch?(socket, dispatch_type) do
      processed_payload = process_event_via_pipeline payload, :server
      case processed_payload do
        {:ok, processed} ->
          socket
          |> Dispatch.handle_dispatch(processed)
          |> handle_dispatch_response

        :halted ->
          Gateway.craft_response []

        {:error, close_payload} ->
          Gateway.craft_response [close_payload]
      end
    else
      :invalid
      |> Payload.create_payload(%{"error" => "invalid dispatch type #{dispatch_type} (are you restricted?)"})
      |> Gateway.craft_response
    end
  end

  defp handle_dispatch_response(dispatch_result) do
    case dispatch_result do
      {:ok, %Payload{} = frame} ->
        [frame]
        |> process_outgoing_event
        |> Gateway.craft_response

      {:ok, {:text, %Payload{}} = frame} ->
        frame
        |> process_outgoing_event
        |> Gateway.craft_response

      {:ok, frames} when is_list(frames) ->
        frames
        |> process_outgoing_event
        |> Gateway.craft_response

      {:error, error} ->
        Gateway.craft_response error
    end
  end

  # TODO: This isn't really the right place for these S:

  def process_outgoing_event({:text, %Payload{} = payload}) do
    {:text, process_outgoing_event(payload)}
  end
  def process_outgoing_event(%Payload{} = payload) do
    case process_event_via_pipeline(payload, :client) do
      {:ok, frame} ->
        frame

      :halted ->
        []

      {:error, close_frame} ->
        close_frame
    end
  end
  def process_outgoing_event(payloads) when is_list(payloads) do
    res = Enum.map payloads, &process_outgoing_event/1
    invalid_filter = fn {:text, frame} -> frame.op == Gateway.opcodes_name()[:invalid] end

    cond do
      Enum.any?(res, &is_nil/1) ->
        []

      Enum.any?(res, invalid_filter) ->
        Enum.filter res, invalid_filter

      true ->
        res
    end
  end

  defp process_event_via_pipeline(%Payload{t: type} = payload, _) when is_nil(type), do: {:ok, payload}
  defp process_event_via_pipeline(%Payload{t: type} = payload, direction) when not is_nil(type) do
    plugins = PluginManager.plugins :all_events
    case plugins do
      [] ->
        {:ok, payload}

      plugins when is_list(plugins) ->
        case run_pipeline(plugins, type, direction, payload, []) do
          {:ok, _frame} = res ->
            res

          :halted ->
            :halted

          {:error, reason, undo_states} ->
            undo_errors =
              undo_states
              # TODO: This should really just append undo states in reverse...
              |> Enum.reverse
              |> unwind_global_undo_stack(direction, type)

            error_payload =
              %{
                reason: reason,
                undo_errors: Enum.map(undo_errors, fn {:error, msg} -> msg end)
              }

            {:error, Payload.error("Error processing plugin event #{type}", error_payload)}
        end
    end
  end

  # credo:disable-for-next-line
  defp run_pipeline([plugin | rest], event, direction, data, undo_states) do
    case plugin.handle_global_event(event, direction, data) do
      {:next, out_frame, plugin_undo_state} when not is_nil(out_frame) and not is_nil(plugin_undo_state) ->
        out_undo_states = Utils.fast_list_concat undo_states, {plugin, plugin_undo_state}
        run_pipeline rest, event, data, out_frame, out_undo_states

      {:next, out_frame, nil} when not is_nil(out_frame) ->
        run_pipeline rest, event, data, out_frame, undo_states

      {:next, out_frame} when not is_nil(out_frame) ->
        run_pipeline rest, event, data, out_frame, undo_states

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

  defp run_pipeline([], _event, _direction, payload, _undo_states) do
    {:ok, payload}
  end

  defp unwind_global_undo_stack(undo_states, direction, event) do
    undo_states
    |> Enum.filter(fn {_, state} -> state != nil end)
    |> Enum.map(fn undo_state -> global_undo(undo_state, direction, event) end)
    # We only want the :error tuple results so that we can report them to the
    # client; successful undos don't need to be reported.
    |> Enum.filter(fn res -> res != :ok end)
  end

  defp global_undo({plugin, undo_state}, direction, event) do
    # We don't just take a list of the undo states here, because really we do
    # not want to halt undo when one encounters an error; instead, we want to
    # continue the undo and then report all errors to the client.
    apply plugin, :global_undo, [event, direction, undo_state]
  end
end
