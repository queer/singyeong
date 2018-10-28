defmodule Singyeong.Gateway.Dispatch do
  alias Singyeong.Gateway.Payload
  alias Singyeong.Metadata.Store
  alias Singyeong.Metadata.Query
  alias Singyeong.Pubsub

  ## DISPATCH EVENTS ##

  # Note: Dispatch handlers will return a list of response frames

  def handle_dispatch(socket, %{"t" => "UPDATE_METADATA", "d" => data} = _payload) do
    try do
      if Store.validate_metadata?(data) do
        # Reduce metadata and update
        data
        #|> Map.keys
        #|> Enum.reduce(%{}, fn(x, acc) ->
        #  Map.put(acc, x, data[x]["value"])
        #end)
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
  def handle_dispatch(_socket, %{"t" => "SEND", "d" => data} = _payload) do
    # Query and route
    %{"sender" => sender, "target" => target, "payload" => payload} = data
    nodes = Query.run_query target
    unless length(nodes) == 0 do
      client = Enum.random nodes
      out = %{
        "sender" => sender,
        "payload" => payload,
        "nonce" => data["nonce"]
      }
      Pubsub.send_message [client], out
      {:ok, []}
    else
      # No nodes matched, warn the client
      # Respond with the same nonce so that clients awaiting a response can fail over
      {:error, [Payload.create_payload(:invalid, %{"error" => "no nodes match query", "d" => %{"nonce" => data["nonce"]}})]}
    end
  end
  def handle_dispatch(_socket, %{"t" => "BROADCAST", "d" => data} = _payload) do
    # This is really just a special case of SEND
    # Query and route
    %{"sender" => sender, "target" => target, "payload" => payload} = data
    nodes = Query.run_query target
    unless length(nodes) == 0 do
      out = %{
        "sender" => sender,
        "payload" => payload,
        "nonce" => data["nonce"]
      }
      Pubsub.send_message nodes, out
      {:ok, []}
    else
      # No nodes matched, warn the client
      # Respond with the same nonce so that clients awaiting a response can fail over
      {:error, [Payload.create_payload(:invalid, %{"error" => "no nodes match query", "d" => %{"nonce" => data["nonce"]}})]}
    end
  end
  def handle_dispatch(_socket, _payload) do
    {:error, Payload.close_with_payload(:invalid, %{"error" => "invalid payload"})}
  end
end
