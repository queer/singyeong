defmodule Singyeong.Queue.Messages do
  alias Singyeong.Cluster

  @spec queue_push(binary(), map()) ::
          {:error, any()}
          | {:timeout, atom() | {atom(), atom()}}
          | {:ok, any(), atom() | {atom(), atom()}}
  def queue_push(name, message) when is_binary(name) and is_map(message) do
    queue_name = :"singyeong_message_queue-#{name}"
    :ra.process_command Cluster.ra_server_id(), {:queue_push, queue_name, message}
  end
end
