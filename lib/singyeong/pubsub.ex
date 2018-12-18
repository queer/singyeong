defmodule Singyeong.Pubsub do
  use GenServer
  require Logger
  alias Singyeong.Gateway.Payload

  @send_queue "singyeong:dispatch:queue:send"
  # @broadcast_queue "singyeong:dispatch:queue:broadcast"

  def start_link(opts) do
    GenServer.start_link __MODULE__, opts, name: __MODULE__
  end

  def init(opts) do
    dsn = opts[:dsn]
    {:ok, pubsub} = Redix.PubSub.start_link dsn
    {:ok, client} = Redix.start_link dsn

    Process.send_after self(), :connect, 250
    state =
      %{
        client: client,
        pubsub: pubsub,
        sockets: %{}
      }
    {:ok, state}
  end

  def handle_info(:connect, state) do
    Redix.PubSub.subscribe state[:pubsub], @send_queue
    # Redix.PubSub.subscribe pubsub, @broadcast_queue
    {:noreply, state}
  end

  def handle_info({:redix_pubsub, pid, ref, :subscribed, %{channel: channel} = _payload}, state) do
    Logger.info "Subscribed to channel #{channel} from pid #{inspect pid} with ref #{inspect ref}"
    {:noreply, state}
  end

  def handle_info({:redix_pubsub, _pid, _ref, :message, %{channel: channel, payload: message} = _publish_payload}, state) do
    # Fork off a new pid to handle it so that we don't block the pubsub pid
    spawn fn ->
        case channel do
          @send_queue ->
            message = Jason.decode! message
            %{"clients" => clients, "payload" => publish_payload} = message
            clients
            |> Enum.filter(fn(x) -> Map.has_key?(state[:sockets], x) end)
            |> Enum.each(fn(client) ->
                socket = state[:sockets][client]
                transport_pid = socket.transport_pid
                if Process.alive?(transport_pid) do
                  send transport_pid, Payload.create_payload(:dispatch, %{
                      "sender" => publish_payload["sender"],
                      "nonce" => publish_payload["nonce"],
                      "payload" => publish_payload["payload"]
                    })
                end
              end)
        end
      end
    {:noreply, state}
  end

  def handle_cast({:send_message, clients, msg}, state) when is_list(clients) and is_map(msg) do
    Redix.command! state[:client], ["PUBLISH", @send_queue, Jason.encode!(%{clients: clients, payload: msg})]
    {:noreply, state}
  end

  def handle_cast({:register_socket, client_id, socket}, state) do
    sockets =
      state[:sockets]
      |> Map.put(client_id, socket)
    {:noreply, %{state | sockets: sockets}}
  end

  def handle_cast({:unregister_socket, client_id}, state) do
    sockets =
      state[:sockets]
      |> Map.delete(client_id)
    {:noreply, %{state | sockets: sockets}}
  end

  def register_socket(client_id, socket) do
    GenServer.cast __MODULE__, {:register_socket, client_id, socket}
  end
  def unregister_socket(client_id) do
    GenServer.cast __MODULE__, {:unregister_socket, client_id}
  end
  def send_message(clients, msg) when is_list(clients) and is_map(msg) do
    # Fill out the nonce to be safe
    msg =
      unless Map.has_key?(msg, "nonce") do
        msg |> Map.put("nonce", nil)
      else
        msg
      end
    GenServer.cast __MODULE__, {:send_message, clients, msg}
  end
end
