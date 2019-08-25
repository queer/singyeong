defmodule Singyeong.Gateway.Dispatch do
  @moduledoc """
  The dispatcher takes in events from clients and processes them in whatever
  manner is needed. This module ties together metadata querying, clustering,
  packet sending / receiving, and "exposes" them all in a way that incoming and
  outgoing messages can take reasonably use.
  """

  alias Singyeong.Cluster
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

  @spec handle_dispatch(Phoenix.Socket.t(), Payload.t()) :: {:error, {:close, {:text, Payload.t()}}} | {:ok, [{:text, Payload.t()}]}
  def handle_dispatch(socket, %Payload{t: "UPDATE_METADATA", d: data} = _payload) do
    try do
      {status, res} = Store.validate_metadata data
      case status do
        :ok ->
          app_id = socket.assigns[:app_id]
          client_id = socket.assigns[:client_id]
          # Store.update_metadata socket.assigns[:app_id], socket.assigns[:client_id], res
          queue_worker = Singyeong.Metadata.UpdateQueue.name app_id, client_id
          pid = Process.whereis queue_worker
          send pid, {:queue, app_id, client_id, res}
          {:ok, []}
        :error ->
          {:error, Payload.close_with_payload(:invalid, %{"error" => "couldn't validate metadata"})}
      end
    rescue
      # Ideally we won't reach this case, but clients can't be trusted :<
      e ->
        formatted =
          Exception.format(:error, e, __STACKTRACE__)
        Logger.error "[DISPATCH] Encountered error handling metadata update:\n#{formatted}"
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
    targets = Cluster.query target
    valid_targets =
      targets
      |> Enum.filter(fn({_, res}) ->
        res != []
      end)
      |> Enum.into(%{})
    # Basically just flattening a list of lists
    matched_client_ids =
      valid_targets
      |> Map.values
      |> Enum.concat

    unless Enum.empty?(matched_client_ids) do
      fake_local_node = Cluster.fake_local_node()
      out = %{
        "sender" => sender,
        "payload" => payload,
        "nonce" => data["nonce"]
      }

      if broadcast do
        for {node, clients} <- valid_targets do
          send_fn = fn ->
            MessageDispatcher.send_dispatch target["application"], clients, out
          end

          case node do
            ^fake_local_node ->
              Task.Supervisor.async Singyeong.TaskSupervisor, send_fn
            _ ->
              Task.Supervisor.async {Singyeong.TaskSupervisor, node}, send_fn
          end
        end
      else
        # Pick random node
        {node, clients} = Enum.random valid_targets
        # Pick a random client from that node's targets
        target_clients = [Enum.random(clients)]
        send_fn = fn ->
          MessageDispatcher.send_dispatch target["application"], target_clients, out
        end
        case node do
          ^fake_local_node ->
            Task.Supervisor.async Singyeong.TaskSupervisor, send_fn
          _ ->
            Task.Supervisor.async {Singyeong.TaskSupervisor, node}, send_fn
        end
      end
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
