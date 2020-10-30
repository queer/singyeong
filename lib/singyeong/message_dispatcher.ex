defmodule Singyeong.MessageDispatcher do
  @moduledoc """
  The message dispatcher is responsible for sending messages to a set of
  client pids inside of an application id.
  """

  alias Singyeong.Cluster
  alias Singyeong.Gateway.Payload
  alias Singyeong.Metadata.Query

  @spec send_with_retry(Plug.Socket.t() | nil, list(term()), non_neg_integer(), Payload.Dispatch.t(), boolean()) :: {:ok, :dropped} | {:ok, :sent} | {:error, :no_route}
  def send_with_retry(_, _, 0, %Payload.Dispatch{target: %Query{droppable: true}}, _) do
    # No matches and droppable, silently drop
    {:ok, :dropped}
  end

  def send_with_retry(socket, _, 0, %Payload.Dispatch{target: %Query{droppable: false} = target, nonce: nonce}, _) do
    # No matches and not droppable, reply to initiator if possible
    if socket != nil and is_pid(socket.transport_pid) and Process.alive?(socket.transport_pid) do
      failure =
        Payload.create_payload :invalid, %{
          "error" => "no nodes match query for query #{inspect target, pretty: true}",
          "d" => %{
            "nonce" => nonce
          }
        }

      send socket.transport_pid, failure
    end
    {:error, :no_route}
  end

  def send_with_retry(_socket, [_ | _] = clients, client_count, %Payload.Dispatch{} = payload, broadcast?) when client_count > 0 do
    if broadcast? do
      # All nodes and all clients
      for {node, node_clients} <- clients do
        distributed_send node, node_clients, "BROADCAST", payload.nonce, payload.payload
      end
    else
      # Pick random node
      {node, clients} = Enum.random clients
      # Pick a random client from that node's targets
      target_client = [Enum.random(clients)]
      distributed_send node, target_client, "SEND", payload.nonce, payload.payload
    end
    {:ok, :sent}
  end

  def send_with_retry(_, _, 0, _, _) do
    {:error, :no_route}
  end

  defp distributed_send(node, clients, type, nonce, payload) do
    fake_local_node = Cluster.fake_local_node()
    send_fn =
      fn ->
        send_dispatch clients, type, nonce, payload
      end

    case node do
      ^fake_local_node ->
        Task.Supervisor.async Singyeong.TaskSupervisor, send_fn

      _ ->
        Task.Supervisor.async {Singyeong.TaskSupervisor, node}, send_fn
    end
  end

  defp send_dispatch(clients, type, nonce, payload) do
    clients
    |> Enum.map(fn client ->
      client.socket_pid
    end)
    |> Enum.filter(&(&1 != nil and Process.alive?(&1)))
    |> Enum.each(fn pid ->
      send pid, Payload.create_payload(:dispatch, type, %{
        "nonce" => nonce,
        "payload" => payload,
      })
    end)
  end
end
