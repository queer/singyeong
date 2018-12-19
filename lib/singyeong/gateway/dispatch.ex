defmodule Singyeong.Gateway.Dispatch do
  alias Singyeong.Gateway.Payload
  alias Singyeong.Metadata.MnesiaStore, as: Store
  alias Singyeong.Metadata.Query
  alias Singyeong.Pubsub
  require Logger

  ## DISPATCH EVENTS ##

  # Note: Dispatch handlers will return a list of response frames

  def handle_dispatch(socket, %{"t" => "UPDATE_METADATA", "d" => data} = _payload) do
    try do
      {status, res} = Store.validate_metadata data
      case status do
        :ok ->
          Store.update_metadata socket.assigns[:app_id], socket.assigns[:client_id], res
          {:ok, []}
        :error ->
          {:error, Payload.close_with_payload(:invalid, %{"error" => "couldn't validate metadata"})}
      end
    rescue
      # Ideally we won't reach this case, but clients can't be trusted :<
      e ->
        Exception.format(:error, e, __STACKTRACE__)
        |> Logger.error
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
      Pubsub.send_message target["application"], [client], out
      {:ok, []}
    else
      # No nodes matched, warn the client
      # Respond with the same nonce so that clients awaiting a response can fail over
      {:error, [
          Payload.create_payload(:invalid, %{
            "error" => "no nodes match query for query #{inspect target, pretty: true}",
            "d" => %{
              "nonce" => data["nonce"]
            }
          })
        ]}
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
      Pubsub.send_message target["application"], nodes, out
      {:ok, []}
    else
      # No nodes matched, warn the client
      # Respond with the same nonce so that clients awaiting a response can fail over
      {:error, [
        Payload.create_payload(:invalid, %{
          "error" => "no nodes match query for query #{inspect target, pretty: true}",
          "d" => %{
            "nonce" => data["nonce"]
          }
        })
      ]}
    end
  end
  def handle_dispatch(_socket, _payload) do
    {:error, Payload.close_with_payload(:invalid, %{"error" => "invalid payload"})}
  end
end
