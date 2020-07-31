defmodule Singyeong.Cluster.StateMachine do
  @behaviour :ra_machine

  @impl :ra_machine
  def init(_args) do
    %{}
  end

  @impl :ra_machine
  def apply(_meta, {:put, key, value}, state) do
    {Map.put(state, key, value), :inserted}
  end

  @impl :ra_machine
  def apply(_meta, {:get, key}, state) do
    reply = Map.get(state, key, nil)
    {state, reply}
  end
end
