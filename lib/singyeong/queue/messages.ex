defmodule Singyeong.Queue.Messages do
  alias Singyeong.CRDT

  @spec create_global_queue(binary()) :: {:ok, integer()} | {:error, binary()}
  def create_global_queue(name) when is_binary(name) do
    queue_name = :"singyeong_message_queue-#{name}"
    case CRDT.create_crdt(queue_name) do
      {:ok, _} = res ->
        res

      {:error, msg} when is_binary(msg) ->
        {:error, "queue error: #{msg}"}
    end
  end
end
