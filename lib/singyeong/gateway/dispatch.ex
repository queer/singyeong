defmodule Singyeong.Gateway.Dispatch do
  alias Singyeong.Gateway.Payload
  alias Singyeong.MnesiaStore, as: Store
  alias Singyeong.Metadata.Query
  alias Singyeong.MessageDispatcher
  require Logger

  # TODO: Config option for this
  @max_send_tries 3
  # TODO: Config option for this too
  @retry_backoff_ms 5_000

  ## DISPATCH EVENTS ##

  def can_dispatch?(socket, event) do
    if socket.assigns[:restricted] do
      case event do
        "UPDATE_METADATA" ->
          true
        _ ->
          false
      end
    else
      true
    end
  end

  # Note: Dispatch handlers will return a list of response frames

  def handle_dispatch(socket, %Payload{t: "UPDATE_METADATA", d: data} = _payload) do
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

  def handle_dispatch(_socket, %Payload{t: "QUERY_NODES", d: data} = _payload) do
    {:ok, [Payload.create_payload(:dispatch, %{"nodes" => Query.run_query(data)})]}
  end

  def handle_dispatch(socket, %Payload{t: "SEND", d: data} = _payload) do
    send_to_clients socket, data, 0, false
    {:ok, []}
  end

  def handle_dispatch(socket, %Payload{t: "BROADCAST", d: data} = _payload) do
    send_to_clients socket, data, 0
    {:ok, []}
  end

  def handle_dispatch(_socket, payload) do
    {:error, Payload.close_with_payload(:invalid, %{"error" => "invalid dispatch payload: #{inspect payload, pretty: true}"})}
  end

  defp send_to_clients(socket, data, tries, broadcast \\ true) do
    %{"sender" => sender, "target" => target, "payload" => payload} = data
    nodes = Query.run_query target
    unless length(nodes) == 0 do
      nodes =
        if broadcast do
          nodes
        else
          [hd(nodes)]
        end
      out = %{
        "sender" => sender,
        "payload" => payload,
        "nonce" => data["nonce"]
      }
      MessageDispatcher.send_message target["application"], nodes, out
    else
      if tries == @max_send_tries do
        failure =
          Payload.create_payload(:invalid, %{
            "error" => "no nodes match query for query #{inspect target, pretty: true}",
            "d" => %{
              "nonce" => data["nonce"]
            }
          })
        send socket.transport_pid, failure
      else
        spawn fn ->
          Process.sleep @retry_backoff_ms
          send_to_clients socket, data, tries + 1, broadcast
        end
      end
    end
  end
end
