defmodule Singyeong.Gateway.Pipeline do
  @moduledoc false

  alias Singyeong.{Gateway, PluginManager, Utils}
  alias Singyeong.Gateway.Payload

  #####################
  ## GLOBAL PIPELINE ##
  #####################

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

  def process_event_via_pipeline(%Payload{t: type} = payload, _) when is_nil(type), do: {:ok, payload}

  def process_event_via_pipeline(%Payload{t: type} = payload, direction) when not is_nil(type) do
    plugins = PluginManager.plugins :all_events
    case plugins do
      [] ->
        {:ok, payload}

      plugins when is_list(plugins) ->
        case run_pipeline(plugins, type, payload, [], [], direction) do
          {:ok, _frame} = res ->
            res

          :halted ->
            :halted

          {:error, reason, undo_states} ->
            undo_errors =
              undo_states
              # TODO: This should really just append undo states in reverse...
              |> Enum.reverse
              |> unwind_undo_stack(direction, type)

            error_payload =
              %{
                reason: reason,
                undo_errors: Enum.map(undo_errors, fn {:error, msg} -> msg end)
              }

            {:error, Payload.error("Error processing plugin event #{type}", error_payload)}
        end
    end
  end

  def run_pipeline(plugins, event, data, frames, undo_states, direction \\ nil)

  def run_pipeline([plugin | rest], event, data, frames, undo_states, direction) do
    {function, args} =
      if direction do
        {:handle_global_event, [event, direction, data]}
      else
        {:handle_event, [event, data]}
      end

    case apply(plugin, function, args) do
      {:next, plugin_frames, plugin_undo_state} when not is_nil(plugin_frames) and not is_nil(plugin_undo_state) ->
        out_frames = if direction, do: plugin_frames, else: Utils.fast_list_concat(frames, plugin_frames)
        data = if direction, do: plugin_frames, else: data
        out_undo_states = Utils.fast_list_concat undo_states, {plugin, plugin_undo_state}
        run_pipeline rest, event, data, out_frames, out_undo_states

      {:next, plugin_frames, nil} when not is_nil(plugin_frames) ->
        out_frames = if direction, do: plugin_frames, else: Utils.fast_list_concat(frames, plugin_frames)
        data = if direction, do: plugin_frames, else: data
        run_pipeline rest, event, data, out_frames, undo_states

      {:next, plugin_frames} when not is_nil(plugin_frames) ->
        out_frames = if direction, do: plugin_frames, else: Utils.fast_list_concat(frames, plugin_frames)
        data = if direction, do: plugin_frames, else: data
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

  def run_pipeline([], _event, _data, frames, _undo_states, direction) do
    if direction do
      {:ok, hd(frames)}
    else
      {:ok, frames}
    end
  end

  def unwind_undo_stack(undo_states, event, direction \\ nil) do
    undo_states
    |> Enum.filter(fn {_, state} -> state != nil end)
    |> Enum.map(fn {plugin, undo_state} ->
      # We don't just take a list of the undo states here, because really we do
      # not want to halt undo when one encounters an error; instead, we want to
      # continue the undo and then report all errors to the client.
      if direction do
        apply plugin, :global_undo, [event, direction, undo_state]
      else
        apply plugin, :undo, [event, undo_state]
      end
    end)
    # We only want the :error tuple results so that we can report them to the
    # client; successful undos don't need to be reported.
    |> Enum.filter(fn res -> res != :ok end)
  end
end
