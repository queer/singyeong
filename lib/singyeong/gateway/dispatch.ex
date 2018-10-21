defmodule Singyeong.Gateway.Dispatch do
  alias Singyeong.Gateway.Payload
  alias Singyeong.Metadata.Store
  alias Singyeong.Metadata.Query

  ## DISPATCH EVENTS ##

  # Note: Dispatch handlers will return a list of response frames

  def handle_dispatch(socket, %{"t" => "UPDATE_METADATA", "d" => data} = _payload) do
    try do
      if Store.validate_metadata?(data) do
        # Reduce metadata and update
        data
        |> Map.keys
        |> Enum.reduce(%{}, fn(x, acc) ->
          Map.put(acc, x, data[x]["value"])
        end)
        |> Store.update_metadata(socket.assigns[:client_id])
        {:ok, []}
      else
        {:error, Payload.close_with_payload(:invalid, %{"error" => "invalid metadata"})}
      end
    rescue
      # Ideally we won't reach this case, but clients can't be trusted :<
      _ ->
        {:error, Payload.close_with_payload(:invalid, %{"error" => "invalid metadata"})}
    end
  end
  def handle_dispatch(_socket, %{"t" => "QUERY_NODES", "d" => data} = _payload) do
    {:ok, [Payload.create_payload(:dispatch, %{"nodes" => Query.run_query(data)})]}
  end
  def handle_dispatch(socket, %{"t" => "SEND", "d" => data} = _payload) do
    # TODO: Query and route
    {:ok, []}
  end
  def handle_dispatch(socket, %{"t" => "BROADCAST", "d" => data} = _payload) do
    # This is really just a special case of SEND
    # TODO: Query and route
    {:ok, []}
  end
  def handle_dispatch(_socket, _payload) do
    {:error, Payload.close_with_payload(:invalid, %{"error" => "invalid payload"})}
  end
end
