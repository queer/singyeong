defmodule Singyeong.Queue.Messages do
  @spec create_global_queue(binary()) :: {:ok, integer()} | {:error, binary()}
  def create_global_queue(name) when is_binary(name) do
    queue_name = :"singyeong_message_queue-#{name}"
    # TODO
  end
end
