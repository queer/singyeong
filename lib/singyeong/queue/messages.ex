defmodule Singyeong.Queue.Messages do
  alias Singyeong.{Cluster, Utils}

  @spec create_global_queue(binary()) :: {:ok, integer()} | {:error, binary()}
  def create_global_queue(name) when is_binary(name) do
    queue_name = :"singyeong_message_queue-#{name}"
    results_map =
      Cluster.run_clustered fn ->
        {:ok, crdt} = DeltaCrdt.start_link(DeltaCrdt.AWLWWMap, sync_interval: 1)
        valid_new_pid? =
          try do
            Process.register crdt, queue_name
            true
          rescue
            ArgumentError ->
              # Couldn't register process, probably means the CRDT pid already
              # exists
              Process.exit crdt, :duplicate_crdt
              false
          end

        cond do
          valid_new_pid? ->
            # If we created the new CRDT pid properly, we can just immediately
            # set its neighbours... I think?
            # TODO: Will this be funny-acting over the network?
            neighbours =
              Cluster.members()
              |> Enum.map(fn node -> {queue_name, node} end)

            DeltaCrdt.set_neighbours crdt, neighbours
            :ok

          queue_name |> Process.whereis |> Process.alive? ->
            # If the queue process already exists, then we don't need to mutate
            # the CRDT pid or anything, so just return.
            :ok

          true ->
            # We couldn't create a new CRDT pid, and there's not an existing
            # pid for it already, which means something broke.
            :error
        end
      end

    %{successes: successes, failures: failures} =
      results_map
      |> Enum.reduce(%{successes: 0, failures: []},
        fn {node, status}, %{successes: successes, failures: failures} = acc ->
          case status do
            :ok ->
              %{acc | successes: successes + 1}

            :error ->
              %{acc | failures: Utils.fast_list_concat(failures, [node])}
          end
      end)

    if failures == [] do
      {:ok, successes}
    else
      {:error, "failed creating queue on nodes: #{inspect failures}"}
    end
  end
end
