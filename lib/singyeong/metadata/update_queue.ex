defmodule Singyeong.Metadata.UpdateQueue do
  @moduledoc """
  A non-WS-pid worker that processes metadata updates for connected clients.
  A metadata queue worker will only process max(50, queue_size / 10) updates
  per second, at most, for the sake of not abusing the CPU. This means that if
  a single client is sending many metadata updates at once, said updates may
  not be visible for several seconds.
  """

  use GenServer
  alias Singyeong.{Config, Metadata, Store}

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

    Process.send_after self(), :process, Config.metadata_queue_interval()
    {:ok, state}
  end

  def handle_info({:queue, {app_id, client_id}, {types, metadata}}, %{queue: queue, queue_size: size} = state) do
    new_queue = :queue.in {{app_id, client_id}, {types, metadata}}, queue
    {:noreply, %{state | queue: new_queue, queue_size: size + 1}}
  end

  def handle_info(:process, state) do
    new_state =
      case process_updates(nil, {%{}, %{}}, state) do
        {{app_id, client_id}, {new_types, new_metadata}, new_state} ->
          :ok = update_metadata app_id, client_id, new_types, new_metadata
          new_state

        {nil, _new_metadata, new_state} -> new_state
        {_, _, new_state} -> new_state
      end

    Process.send_after self(), :process, Config.metadata_queue_interval()
    {:noreply, new_state}
  end

  defp update_metadata(app_id, client_id, new_types, new_metadata) when nil not in [
    app_id,
    client_id,
    new_types,
    new_metadata,
  ] do
    {:ok, client} = Store.get_client app_id, client_id
    {:ok, _} =
      case Config.metadata_update_strategy() do
        :merge ->
          Store.update_client %{
            client
            | metadata: Map.merge(client.metadata, new_metadata),
              metadata_types: Map.merge(client.metadata_types, new_types),
          }

        :replace ->
          base =
            client.metadata
            |> Enum.filter(fn {k, _} -> k in Metadata.forbidden_keys() end)
            |> Map.new

          Store.update_client %{
            client
            | metadata: Map.merge(new_metadata, base),
              metadata_types: Map.merge(new_types, Metadata.base_types()),
          }
      end

    :ok
  end
  defp update_metadata(_, _, _, _), do: :ok

  defp process_updates(client_id, {new_types, new_metadata}, %{queue_size: 0} = state) do
    {client_id, {new_types, new_metadata}, state}
  end

  defp process_updates(_client_id, {new_types, new_metadata}, %{queue_size: queue_size, queue: queue} = state) do
    next_payload = :queue.out queue
    {new_client_id, {next_types, next_metadata}, new_queue, new_queue_size} =
      case next_payload do
        {{:value, item}, new_queue} ->
          # If we get a value out of the queue, deconstruct it and do a
          # metadata update.
          {client_id, {incoming_types, incoming_metadata}} = item
          {client_id, {Map.merge(new_types, incoming_types), Map.merge(new_metadata, incoming_metadata)}, new_queue, queue_size - 1}

        {:empty, new_queue} ->
          # If the queue is actually empty but we were out of sync, then we
          # reset the queue size.
          # This *shouldn't* be possible, but who knows /shrug
          {nil, {nil, nil}, new_queue, 0}

        _ ->
          # If, for some reason, we get something unexpected, just return the
          # queue itself. This *shouldn't* happen, but who knows.
          {nil, {nil, nil}, queue, queue_size}
      end

    process_updates new_client_id, {next_types, next_metadata}, %{state | queue: new_queue, queue_size: new_queue_size}
  end

  def name(app_id, client_id) do
    :"#{__MODULE__}:#{app_id}:#{client_id}"
  end
end
