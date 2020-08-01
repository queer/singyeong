defmodule Singyeong.Cluster.StateMachine do
  alias Singyeong.Utils

  @behaviour :ra_machine

  @impl :ra_machine
  def init(_args) do
    %{queues: %{}}
  end

  @impl :ra_machine
  def apply(_meta, {:put, key, value}, state) do
    {Map.put(state, key, value), :inserted}
  end

  @impl :ra_machine
  def apply(_meta, {:get, key}, state) do
    reply = Map.get state, key, nil
    {state, reply}
  end

  @impl :ra_machine
  def apply(_meta, {:queue_push, name, msg}, %{queues: queues} = state) do
    new_queue =
      case Map.get(queues, name, nil) do
        [] ->
          [msg]

        [_] = queue ->
          Utils.fast_list_concat queue, msg

        [_ | _] = queue ->
          Utils.fast_list_concat queue, msg

        nil ->
          [msg]
      end

    {%{state | queues: %{queues | name => new_queue}}, :ok}
  end
end
