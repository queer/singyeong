defmodule Singyeong.CRDT do
  alias Singyeong.{Cluster, Utils}

  @spec create_crdt(binary()) :: {:ok, integer()} | {:error, binary()}
  def create_crdt(name) when is_atom(name) do
    results_map =
      Cluster.run_clustered fn ->
        # TODO: sync_interval is ms I believe?
        {:ok, crdt} = DeltaCrdt.start_link DeltaCrdt.AWLWWMap, sync_interval: 50
        valid_new_pid? =
          try do
            Process.register crdt, name
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
              |> Enum.map(fn node -> {name, node} end)

            DeltaCrdt.set_neighbours crdt, neighbours

            # Register CRDT for periodic neighbour resyncs
            Cluster.register_crdt name, crdt
            :ok

          name |> Process.whereis |> Process.alive? ->
            # If the CRDT process already exists, then we don't need to mutate
            # the pid or anything, so just return.
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
      {:error, "failed creating crdt on nodes: #{inspect failures}"}
    end
  end
end
