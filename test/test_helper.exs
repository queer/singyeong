defmodule RaftHelpers do
  alias RaftFleet.Manager.State

  # Thanks skirino ^^
  # https://github.com/skirino/raft_fleet/blob/9c2a5293794da837ad78fb41c700cd38bd0b08fc/test/test_helper.exs#L58-L73
  def wait_for_activation(_, 0), do: raise "activation not completed!"
  def wait_for_activation(node, tries_remaining) do
    state = :sys.get_state {RaftFleet.Manager, node}
    if State.phase(state) == :active do
      :ok
    else
      :timer.sleep 1_000
      wait_for_activation node, tries_remaining - 1
    end
  catch
    :exit, {:noproc, _} ->
      :timer.sleep 1_000
      wait_for_activation node, tries_remaining - 1
  end
end

"Mnesia.*/" |> Path.wildcard |> File.rm_rf!
:ok = RaftFleet.activate "test_zone"
RaftHelpers.wait_for_activation Node.self(), 3

IO.puts ">> Starting ExUnit!"
ExUnit.start()
