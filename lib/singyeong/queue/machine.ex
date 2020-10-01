defmodule Singyeong.Queue.Machine do
  @behaviour RaftedValue.Data

  require Logger

  def new do
    {:queue.new(), 0}
  end

  def command({queue, len}, {:push, value}) do
    new_queue = :queue.in value, queue
    {:ok, {new_queue, len + 1}}
  end

  def command({queue, len} = state, :pop) do
    if len == 0 do
      {nil, state}
    else
      {{:value, value}, new_queue} = :queue.out queue
      {value, {new_queue, len - 1}}
    end
  end

  def query({queue, _}, :peek) do
    case :queue.peek(queue) do
      {:value, value} ->
        value

      :empty ->
        nil
    end
  end

  def query({_, len}, :length) do
    Logger.warn "!!! QUERYING QUEUE LENGTH !!!"
    len
  end
end
