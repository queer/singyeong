defmodule Singyeong.Metadata.UpdateQueue do
  @moduledoc """
  A non-WS-pid worker that processes metadata updates for connected clients.
  A metadata queue worker will only process max(50, queue_size / 10) updates
  per second, at most, for the sake of not abusing the CPU. This means that if
  a single client is sending many metadata updates at once, said updates may
  not be visible for several seconds.
  """

  alias Singyeong.MnesiaStore, as: Store

  use GenServer

  def start_link(opts) do
    GenServer.start_link __MODULE__, opts, name: opts[:name]
  end

  def init(opts) do
    # We just let opts be a map that is our state
    state =
      opts
      |> Map.put(:queue, :queue.new())
      # We track the queue size ourselves, since the Erlang :queue module
      # doesn't store this as part of the queue itself, but rather recomputes
      # it each time you call :queue.len/1.
      |> Map.put(:queue_size, 0)

    Process.send_after self(), :process, 1000
    {:ok, state}
  end

  def handle_info({:queue, app_id, client_id, metadata}, state) do
    new_queue = :queue.in {app_id, client_id, metadata}, state[:queue]
    queue_size = state[:queue_size] + 1
    {:noreply, %{state | queue: new_queue, queue_size: queue_size}}
  end

  def handle_info(:process, %{queue_size: queue_size} = state) do
    new_state = process_updates state, max(50, div(queue_size, 10))
    Process.send_after self(), :process, 1000
    {:noreply, new_state}
  end

  defp process_updates(%{queue_size: queue_size, queue: queue} = state, count) do
    if queue_size > 0 and count > 0 do
      res = :queue.out queue
      {new_queue, new_queue_size} =
        case res do
          {{:value, item}, new_queue} ->
            # If we get a value out of the queue, deconstruct it and do a
            # metadata update.
            {app_id, client_id, metadata} = item
            Store.update_metadata app_id, client_id, metadata
            {new_queue, queue_size - 1}

          {:empty, new_queue} ->
            # If the queue is actually empty but we were out of sync, then we
            # reset the queue size.
            {new_queue, 0}

          _ ->
            # If, for some reason, we get something unexpected, just return the
            # queue itself. This *shouldn't* happen, but who knows.
            {queue, queue_size}
        end

      process_updates %{state | queue: new_queue, queue_size: new_queue_size}, count - 1
    else
      state
    end
  end

  def name(app_id, client_id) do
    :"#{__MODULE__}:#{app_id}:#{client_id}"
  end
end
