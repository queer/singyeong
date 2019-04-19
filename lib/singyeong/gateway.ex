defmodule Singyeong.Gateway do
  alias Singyeong.Gateway.Payload
  alias Singyeong.Gateway.Dispatch
  alias Singyeong.Metadata
  alias Singyeong.MnesiaStore, as: Store
  alias Singyeong.MessageDispatcher
  alias Singyeong.Env

  require Logger

  @heartbeat_interval 45_000

  @opcodes_name %{
    # recv
    :hello          => 0,
    # send
    :identify       => 1,
    # recv
    :ready          => 2,
    # recv
    :invalid        => 3,
    # both
    :dispatch       => 4,
    # send
    :heartbeat      => 5,
    # recv
    :heartbeat_ack  => 6,
    # recv
    # TODO: Build real clustering so that this actually does something :^(
    :goodbye        => 7,
  }
  @opcodes_id %{
    # recv
    0 => :hello,
    # send
    1 => :identify,
    # recv
    2 => :ready,
    # recv
    3 => :invalid,
    # both
    4 => :dispatch,
    # send
    5 => :heartbeat,
    # recv
    6 => :heartbeat_ack,
    # recv
    7 => :goodbye,
  }

  defmodule GatewayResponse do
    # The empty map for response is effectively just a noop
    # If the assigns map isn't empty, everything in it will be assigned to the socket
    defstruct response: [],
      assigns: %{}
  end

  ## HELPERS ##

  def heartbeat_interval, do: @heartbeat_interval
  def opcodes_name, do: @opcodes_name
  def opcodes_id, do: @opcodes_id

  defp craft_response(response, assigns \\ %{})
      when (is_tuple(response) or is_list(response)) and is_map(assigns)
      do
    %GatewayResponse{response: response, assigns: assigns}
  end

  ## INCOMING PAYLOAD ##

  # handle_payload doesn't have any typespecs because dialyzer gets a n g e r y ;_;

  # @spec handle_payload(Phoenix.Socket.t, binary()) :: GatewayResponse.t
  def handle_payload(socket, {opcode, payload}) when is_atom(opcode) and is_binary(payload) do
    {status, msg} =
      case opcode do
        :text ->
          Jason.decode payload
        :binary ->
          try do
            term = :erlang.binary_to_term payload
            {:ok, term}
          rescue
            _ ->
              {:error, nil}
          end
      end
    case status do
      :ok ->
        handle_payload socket, msg
      _ ->
        Payload.close_with_payload(:invalid, %{"error" => "cannot decode payload"})
        |> craft_response
    end
  end

  # @spec handle_payload(Phoenix.Socket.t, %{binary() => any()}) :: GatewayResponse.t
  def handle_payload(socket, %{"op" => op, "d" => d} = payload) when is_integer(op) and is_map(d) do
    handle_payload_internal socket, %{
      "op" => op,
      "d" => d,
      "t" => payload["t"] || ""
    }
  end

  # @spec handle_payload(Phoenix.Socket.t, any()) :: GatewayResponse.t
  def handle_payload(_socket, _payload) do
    Payload.close_with_payload(:invalid, %{"error" => "bad payload"})
    |> craft_response
  end

  defp handle_payload_internal(socket, %{"op" => op, "d" => d, "t" => t} = _payload) do
    should_disconnect =
      unless is_nil(socket.assigns[:app_id]) and is_nil(socket.assigns[:client_id]) do
        # If both are NOT nil, then we need to check last heartbeat
        {:ok, last} = Store.get_metadata socket.assigns[:app_id], socket.assigns[:client_id], Metadata.last_heartbeat_time()
        last + (@heartbeat_interval * 1.5) < :os.system_time(:millisecond)
      else
        false
      end

    if should_disconnect do
      Payload.close_with_payload(:invalid, %{"error" => "heartbeat took too long"})
      |> craft_response
    else
      payload_obj = %Payload{op: op, d: d, t: t}
      try_handle_event socket, payload_obj
    end
  end

  defp try_handle_event(socket, payload) do
    op = payload.op
    named = @opcodes_id[op]
    if named != :identify and socket.assigns[:client_id] == nil do
      # Try to halt it as soon as possible so that we don't waste time on it
      Payload.close_with_payload(:invalid, %{"error" => "sent payload with non-identify opcode without identifying first"})
      |> craft_response
    else
      try do
        case named do
          :identify ->
            handle_identify socket, payload
          :dispatch ->
            handle_dispatch socket, payload
          :heartbeat ->
            # We only really do heartbeats to keep clients alive.
            # cowboy server will automatically disconnect after some period if
            # no messages come over the socket, so the client is responsible
            # for keeping itself alive.
            handle_heartbeat socket, payload
          _ ->
            handle_invalid_op socket, op
        end
      rescue
        e ->
          formatted =
            Exception.format(:error, e, __STACKTRACE__)
          Logger.error "[GATEWAY] Encountered error handling gateway payload: #{formatted}"
          Payload.close_with_payload(:invalid, %{"error" => "internal server error"})
          |> craft_response
      end
    end
  end

  ## SOCKET CLOSED ##

  def handle_close(socket) do
    unless is_nil(socket.assigns[:app_id]) and is_nil(socket.assigns[:client_id]) do
      MessageDispatcher.unregister_socket socket
      Store.delete_client socket.assigns[:app_id], socket.assigns[:client_id]
      Store.remove_socket socket.assigns[:app_id], socket.assigns[:client_id]
      Store.remove_socket_ip socket.assigns[:app_id], socket.assigns[:client_id]
    end
  end

  ## OP HANDLING ##

  @spec handle_identify(Phoenix.Socket.t, Payload.t) :: GatewayResponse.t
  def handle_identify(socket, payload) do
    d = payload.d
    client_id = d["client_id"]
    app_id = d["application_id"]
    tags = Map.get d, "tags", []
    if is_binary(client_id) and is_binary(app_id) do
      # Check app/client IDs to ensure validity
      restricted = Env.auth() != d["auth"]
      etf =
        if restricted do
          false
        else
          d["etf"]
        end
      # If the client doesn't specify its own ip (eg. for routing to a specific
      # port for HTTP), we fall back to the socket-assign port, which is
      # derived from peer data in the transport.
      ip = d["ip"] || socket.assigns[:ip]
      cond do
        not Store.client_exists?(app_id, client_id) ->
          # Client doesn't exist, add to store and okay it
          finish_identify app_id, client_id, tags, socket, ip, restricted, etf
        Store.client_exists?(app_id, client_id) and d["reconnect"] and not restricted ->
          # Client does exist, but this is a reconnect, so add to store and okay it
          finish_identify app_id, client_id, tags, socket, ip, restricted, etf
        true ->
          # If we already have a client, reject outright
          Payload.close_with_payload(:invalid, %{"error" => "client id #{client_id} already registered for application id #{app_id}"})
          |> craft_response
      end
    else
      handle_missing_data()
    end
  end

  defp finish_identify(app_id, client_id, tags, socket, ip, restricted, etf) do
    # Add client to the store and update its tags if possible
    Store.add_client app_id, client_id
    unless restricted do
      # Update tags
      Store.set_tags app_id, client_id, tags
      # Update ip
      Store.add_socket_ip app_id, client_id, ip
    end
    # Last heartbeat time is the current time to avoid incorrect disconnects
    Store.update_metadata app_id, client_id, Metadata.last_heartbeat_time(), :os.system_time(:millisecond)
    # Update restriction status for queries to take advantage of
    Store.update_metadata app_id, client_id, Metadata.restricted(), restricted
    # Update ETF status for queries to take advantage of
    Store.update_metadata app_id, client_id, Metadata.etf(), etf
    # Register with pubsub
    MessageDispatcher.register_socket app_id, client_id, socket
    if restricted do
      Logger.info "[GATEWAY] Got new RESTRICTED socket #{app_id}:#{client_id} @ #{ip}"
    else
      Logger.info "[GATEWAY] Got new socket #{app_id}:#{client_id} @ #{ip}"
    end
    # Respond to the client
    Payload.create_payload(:ready, %{"client_id" => client_id, "restricted" => restricted})
    |> craft_response(%{client_id: client_id, app_id: app_id, restricted: restricted, etf: etf})
  end

  def handle_dispatch(socket, payload) do
    dispatch_type = payload.t
    if Dispatch.can_dispatch?(socket, dispatch_type) do
      res = Dispatch.handle_dispatch socket, payload
      case res do
        {:ok, frames} ->
          frames
          |> craft_response
        {:error, error} ->
          error
          |> craft_response
      end
    else
      Payload.create_payload(:invalid, %{"error" => "invalid dispatch type #{dispatch_type} (are you restricted?)"})
      |> craft_response
    end
  end

  def handle_heartbeat(socket, _payload) do
    app_id = socket.assigns[:app_id]
    client_id = socket.assigns[:client_id]
    if not is_nil(client_id) and is_binary(client_id) do
      # When we ack the heartbeat, update last heartbeat time
      Store.update_metadata app_id, client_id, Metadata.last_heartbeat_time(), :os.system_time(:millisecond)
      Payload.create_payload(:heartbeat_ack, %{"client_id" => socket.assigns[:client_id]})
      |> craft_response
    else
      handle_missing_data()
    end
  end

  defp handle_missing_data do
    Payload.close_with_payload(:invalid, %{"error" => "payload has no data"})
    |> craft_response
  end

  defp handle_invalid_op(_socket, op) do
    Payload.close_with_payload(:invalid, %{"error" => "invalid client op #{inspect op}"})
    |> craft_response
  end

  # This is here because we need to be able to send it immediately from
  # the socket transport layer
  def hello do
    %{
      "heartbeat_interval" => @heartbeat_interval
    }
  end
end
