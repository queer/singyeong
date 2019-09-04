defmodule Singyeong.Gateway do
  @moduledoc """
  The "gateway" into the 신경 system. All messages that a client sends or
  receives over its websocket connection come through the gateway for
  preprocessing, authentication, and other things.
  """

  alias Singyeong.Gateway.Payload
  alias Singyeong.Gateway.Dispatch
  alias Singyeong.Metadata
  alias Singyeong.MnesiaStore, as: Store
  alias Singyeong.MessageDispatcher
  alias Singyeong.Env
  require Logger

  ## STATIC DATA ##

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

  @valid_encodings [
    "json",
    "msgpack",
    "etf",
  ]

  ## STRUCT DEFINITIONS ##

  defmodule GatewayResponse do
    @moduledoc """
    A packet being sent from the gateway to a client.
    """

    @type t :: %__MODULE__{response: [] | [any()] | {:text, any()} | {:close, {:text, any()}}, assigns: map()}

    # The empty map for response is effectively just a noop
    # If the assigns map isn't empty, everything in it will be assigned to the socket
    defstruct response: [],
      assigns: %{}
  end

  ## HELPERS ##

  @spec heartbeat_interval() :: integer()
  def heartbeat_interval, do: @heartbeat_interval
  @spec opcodes_name() :: %{atom() => integer()}
  def opcodes_name, do: @opcodes_name
  @spec opcodes_id() :: %{integer() => atom()}
  def opcodes_id, do: @opcodes_id

  defp craft_response(response, assigns \\ %{})
      when (is_tuple(response) or is_list(response)) and is_map(assigns)
      do
    %GatewayResponse{response: response, assigns: assigns}
  end

  @spec validate_encoding(binary()) :: boolean()
  def validate_encoding(encoding) when is_binary(encoding), do: encoding in @valid_encodings

  @spec encode(Phoenix.Socket.t(), {any(), any()} | Singyeong.Gateway.Payload.t()) :: {:binary, any()} | {:text, binary()}
  def encode(socket, data) do
    encoding = socket.assigns[:encoding] || "json"
    case data do
      {_, payload} ->
        encode_real encoding, payload
      _ ->
        encode_real encoding, data
    end
  end

  @spec encode_real(binary(), any()) :: {:binary, binary()} | {:text, binary()}
  def encode_real(encoding, payload) do
    payload = to_outgoing payload
    case encoding do
      "json" ->
        {:ok, term} = Jason.encode payload
        {:text, term}
      "msgpack" ->
        {:ok, term} = Msgpax.pack payload
        # msgpax returns iodata, so we convert it to binary for consistency
        {:binary, IO.iodata_to_binary(term)}
      "etf" ->
        term = :erlang.term_to_binary payload
        {:binary, term}
    end
  end
  defp to_outgoing(%{__struct__: _} = payload) do
    Map.from_struct payload
  end
  defp to_outgoing(payload) do
    payload
  end

  ## INCOMING PAYLOADS ##

  @spec handle_incoming_payload(Phoenix.Socket.t(), {atom(), binary()}) :: GatewayResponse.t()
  def handle_incoming_payload(socket, {opcode, payload}) when is_atom(opcode) do
    encoding = socket.assigns[:encoding]
    restricted = socket.assigns[:restricted]
    # Decode incoming packets based on the state of the socket
    {status, msg} =
      case {opcode, encoding} do
        {:text, "json"} ->
          # JSON can just be directly encoded
          Jason.decode payload
        {:binary, "msgpack"} ->
          # MessagePack has to be unpacked and error-checked
          {e, d} = Msgpax.unpack payload
          case e do
            :ok ->
              {:ok, d}
            :error ->
              # We convert the exception into smth more useful
              {:error, Exception.message(d)}
          end
        {:binary, "etf"} ->
          case restricted do
            true ->
              # If the client is restricted, but is sending us ETF, make it go
              # away
              {:error, "restricted clients may not use ETF"}
            false ->
              # If the client is NOT restricted and sends ETF, decode it.
              # In this particular case, we trust that the client isn't stupid
              # about the ETF it's sending
              term = :erlang.binary_to_term payload
              {:ok, term}
            nil ->
              # If we don't yet know if the client will be restricted, decode
              # it in safe mode
              term = :erlang.binary_to_term payload, [:safe]
              {:ok, term}
          end
        _ ->
          {:error, "invalid opcode/encoding combo: {#{opcode}, #{encoding}}"}
      end

    case status do
      :ok ->
        handle_payload socket, msg
      :error ->
        error_msg =
          if msg do
            msg
          else
            "cannot decode payload"
          end
        Payload.close_with_payload(:invalid, %{"error" => error_msg})
        |> craft_response
    end
  end

  @spec handle_payload(Phoenix.Socket.t(), Payload.t()) :: GatewayResponse.t()
  def handle_payload(socket, %{"op" => op, "d" => d} = payload) when is_integer(op) and is_map(d) do
    handle_payload_internal socket, %{
      "op" => op,
      "d" => d,
      "t" => payload["t"] || "",
    }
  end

  # Handle malformed packets
  # This SHOULDN'T be called, but clients can't be trusted smh >:I
  def handle_payload(_socket, _payload) do
    Payload.close_with_payload(:invalid, %{"error" => "bad payload"})
    |> craft_response
  end

  defp handle_payload_internal(socket, %{"op" => op, "d" => d, "t" => t} = _payload) do
    # Check if we need to disconnect the client for taking too long to heartbeat
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
      # If we don't have a client id assigned, then the client hasn't
      # identified itself yet and as such shouldn't be allowed to do anything
      # BUT identify
      # We try to halt it as soon as possible so that we don't waste time on it
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
            # The cowboy server will automatically disconnect after some period
            # if no messages come over the socket, so the client is responsible
            # for keeping itself alive.
            handle_heartbeat socket, payload
          _ ->
            handle_invalid_op socket, op
        end
      rescue
        e ->
          formatted =
            Exception.format(:error, e, __STACKTRACE__)
          Logger.error "[GATEWAY] Encountered error handling gateway payload:\n#{formatted}"
          Payload.close_with_payload(:invalid, %{"error" => "internal server error"})
          |> craft_response
      end
    end
  end

  ## SOCKET CLOSED ##

  def handle_close(socket) do
    unless is_nil(socket.assigns[:app_id]) and is_nil(socket.assigns[:client_id]) do
      app_id = socket.assigns[:app_id]
      client_id = socket.assigns[:client_id]

      cleanup socket, app_id, client_id
    end
  end

  def cleanup(socket, app_id, client_id) do
    MessageDispatcher.unregister_socket socket
    Store.delete_client app_id, client_id
    Store.remove_socket app_id, client_id
    Store.remove_socket_ip app_id, client_id
    Store.delete_tags app_id, client_id

    queue_worker = Singyeong.Metadata.UpdateQueue.name app_id, client_id
    pid = Process.whereis queue_worker
    DynamicSupervisor.terminate_child Singyeong.MetadataQueueSupervisor, pid
  end

  ## OP HANDLING ##

  @spec handle_identify(Phoenix.Socket.t(), Payload.t) :: GatewayResponse.t
  def handle_identify(socket, payload) do
    d = payload.d
    client_id = d["client_id"]
    app_id = d["application_id"]

    tags = Map.get d, "tags", []
    if is_binary(client_id) and is_binary(app_id) do
      # Check app/client IDs to ensure validity
      restricted = Env.auth() != d["auth"]
      encoding = socket.assigns[:encoding]
      # If the client doesn't specify its own ip (eg. for routing to a specific
      # port for HTTP), we fall back to the socket-assign port, which is
      # derived from peer data in the transport.
      ip = d["ip"] || socket.assigns[:ip]
      cond do
        not Store.client_exists?(app_id, client_id) ->
          # Client doesn't exist, add to store and okay it
          finish_identify app_id, client_id, tags, socket, ip, restricted, encoding
        Store.client_exists?(app_id, client_id) and d["reconnect"] and not restricted ->
          # Client does exist, but this is a reconnect, so add to store and okay it
          finish_identify app_id, client_id, tags, socket, ip, restricted, encoding
        true ->
          # If we already have a client, reject outright
          Payload.close_with_payload(:invalid, %{"error" => "client id #{client_id} already registered for application id #{app_id}"})
          |> craft_response
      end
    else
      handle_missing_data()
    end
  end

  defp finish_identify(app_id, client_id, tags, socket, ip, restricted, encoding) do
    # Start metadata update queue worker
    queue_worker = Singyeong.Metadata.UpdateQueue.name app_id, client_id
    DynamicSupervisor.start_child Singyeong.MetadataQueueSupervisor,
      {Singyeong.Metadata.UpdateQueue, %{name: queue_worker}}
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
    # Update encoding status for queries to take advantage of
    Store.update_metadata app_id, client_id, Metadata.encoding(), encoding
    # Register with pubsub
    MessageDispatcher.register_socket app_id, client_id, socket
    if restricted do
      Logger.info "[GATEWAY] Got new RESTRICTED socket #{app_id}:#{client_id} @ #{ip}"
    else
      Logger.info "[GATEWAY] Got new socket #{app_id}:#{client_id} @ #{ip}"
    end
    # Respond to the client
    Payload.create_payload(:ready, %{"client_id" => client_id, "restricted" => restricted})
    |> craft_response(%{app_id: app_id, client_id: client_id, restricted: restricted, encoding: encoding})
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

  # This is here because we need to be able to send it immediately from the
  # socket transport layer, but it wouldn't really make sense elsewhere.
  def hello do
    %{
      "heartbeat_interval" => @heartbeat_interval
    }
  end
end
