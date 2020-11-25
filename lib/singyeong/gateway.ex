defmodule Singyeong.Gateway do
  @moduledoc """
  The "gateway" into the 신경 system. All messages that a client sends or
  receives over its websocket connection come through the gateway for
  preprocessing, authentication, and other things.
  """

  alias Singyeong.Gateway.{Dispatch, Payload}
  alias Singyeong.Metadata
  alias Singyeong.Metadata.UpdateQueue
  alias Singyeong.PluginManager
  alias Singyeong.Store
  alias Singyeong.Store.Client
  alias Singyeong.Utils
  require Logger

  ## STATIC DATA ##

  @heartbeat_interval 45_000

  @opcodes_name %{
    # recv
    :hello         => 0,
    # send
    :identify      => 1,
    # recv
    :ready         => 2,
    # recv
    :invalid       => 3,
    # both
    :dispatch      => 4,
    # send
    :heartbeat     => 5,
    # recv
    :heartbeat_ack => 6,
    # recv
    :goodbye       => 7,
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

    @type t :: %__MODULE__{
      response: [] | [Payload.t()] | {:text, Payload.t()} | {:close, {:text, Payload.t()}},
      assigns: map()
    }

    # The empty map for response is effectively just a noop
    # If the assigns map isn't empty, everything in it will be assigned to the socket
    defstruct response: [], assigns: %{}
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

  @spec encode(Phoenix.Socket.t(), {any(), any()} | Singyeong.Gateway.Payload.t())
    :: {:binary, any()} | {:text, binary()}
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
    {status, msg} = decode_payload opcode, payload, encoding, restricted

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

        Payload.close_with_error(error_msg)
        |> craft_response
    end
  end

  defp decode_payload(opcode, payload, encoding, restricted) do
    case {opcode, encoding} do
      {:text, "json"} ->
        # JSON has to be error-checked for error conversion properly
        {status, data} = Jason.decode payload
        case status do
          :ok ->
            {:ok, Payload.from_map(data)}

          :error ->
            {:error, Exception.message(data)}
        end

      {:binary, "msgpack"} ->
        # MessagePack has to be unpacked and error-checked
        {status, data} = Msgpax.unpack payload
        case status do
          :ok ->
            {:ok, Payload.from_map(data)}

          :error ->
            # We convert the exception into smth more useful
            {:error, Exception.message(data)}
        end

      {:binary, "etf"} ->
        decode_etf payload, restricted

      _ ->
        {:error, "invalid opcode/encoding combo: {#{opcode}, #{encoding}}"}
    end
  rescue
    _ ->
      {:error, "Couldn't decode payload"}
  end

  defp decode_etf(payload, restricted) do
    case restricted do
      true ->
        # If the client is restricted, but is sending us ETF, make it go
        # away
        {:error, "restricted clients may not use ETF"}

      false ->
        # If the client is NOT restricted and sends ETF, decode it.
        # In this particular case, we trust that the client isn't stupid
        # about the ETF it's sending
        term =
          payload
          |> :erlang.binary_to_term
          |> Utils.stringify_keys
          |> Payload.from_map

        {:ok, term}

      nil ->
        # If we don't yet know if the client will be restricted, decode
        # it in safe mode
        term =
          payload
          |> :erlang.binary_to_term([:safe])
          |> Utils.stringify_keys
          |> Payload.from_map

        {:ok, term}
    end
  end

  @spec handle_payload(Phoenix.Socket.t(), Payload.t()) :: GatewayResponse.t()
  def handle_payload(socket, %Payload{} = payload) do
    # Check if we need to disconnect the client for taking too long to heartbeat
    should_disconnect =
      with app_id when not is_nil(app_id) <- socket.assigns[:app_id],
           client_id when not is_nil(client_id) <- socket.assigns[:client_id],
           {:ok, %Client{
             metadata: metadata,
             client_id: ^client_id,
             app_id: ^app_id
           }} <- Store.get_client(client_id),
           last_heartbeat when is_integer(last_heartbeat)
             <- metadata[Metadata.last_heartbeat_time()]
      do
        last_heartbeat + (@heartbeat_interval * 1.5) < Utils.now()
      else
        _ -> false
      end

    if should_disconnect do
      Payload.close_with_error("heartbeat took too long")
      |> craft_response
    else
      try_handle_event socket, payload
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
      Payload.close_with_error("sent payload with non-identify opcode without identifying first")
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
          formatted = Exception.format :error, e, __STACKTRACE__
          Logger.error "[GATEWAY] Encountered error handling gateway payload:\n#{formatted}"
          :invalid
          |> Payload.close_with_error("internal server error")
          |> craft_response
      end
    end
  end

  ## SOCKET CLOSED ##

  def handle_close(socket) do
    unless is_nil(socket.assigns[:app_id]) and is_nil(socket.assigns[:client_id]) do
      app_id = socket.assigns[:app_id]
      client_id = socket.assigns[:client_id]
      Logger.info "[GATEWAY] Cleaning up #{app_id}:#{client_id}"

      cleanup app_id, client_id
    end
  end

  def cleanup(app_id, client_id) do
    {:ok, :ok} =
      client_id
      |> Store.get_client
      |> elem(1)
      |> Store.remove_client

    Logger.debug "[GATEWAY] [#{app_id}:#{client_id}] Removed from store"

    queue_worker = UpdateQueue.name app_id, client_id
    pid = Process.whereis queue_worker
    if pid do
      DynamicSupervisor.terminate_child Singyeong.MetadataQueueSupervisor, pid
      Logger.debug "[GATEWAY] [#{app_id}:#{client_id}] Terminated update queue"
    end
  end

  ## OP HANDLING ##

  @spec handle_identify(Phoenix.Socket.t(), Payload.t()) :: GatewayResponse.t()
  def handle_identify(socket, payload) do
    d = payload.d
    client_id = d["client_id"]
    app_id = d["application_id"]

    if is_binary(client_id) and is_binary(app_id) do
      # If the client doesn't specify its own ip (eg. for routing to a specific
      # port for HTTP), we fall back to the socket-assign port, which is
      # derived from peer data in the transport.
      ip = d["ip"] || socket.assigns[:ip]
      auth_status = PluginManager.plugin_auth d["auth"], ip

      case auth_status do
        status when status in [:ok, :restricted] ->
          restricted = status == :restricted
          encoding = socket.assigns[:encoding]
          unless Store.client_exists?(client_id) do
            # Client doesn't exist, add to store and okay it
            finish_identify app_id, client_id, socket, ip, restricted, encoding
          else
            # If we already have a client, reject outright
            Payload.close_with_error("#{client_id}: already registered for app #{app_id}")
            |> craft_response
          end

        {:error, errors} ->
          Payload.close_with_error("Errors occurred during auth:", errors)
          |> craft_response
      end
    else
      handle_missing_data()
    end
  end

  defp finish_identify(app_id, client_id, socket, ip, restricted, encoding) do
    queue_worker = UpdateQueue.name app_id, client_id
    DynamicSupervisor.start_child Singyeong.MetadataQueueSupervisor,
      {UpdateQueue, %{name: queue_worker}}

    client_ip = if restricted, do: nil, else: ip

    client =
      %Client{
        app_id: app_id,
        client_id: client_id,
        metadata: %{
          Metadata.last_heartbeat_time() => Utils.now(),
          Metadata.restricted() => restricted,
          Metadata.encoding() => encoding,
          Metadata.ip() => client_ip,
        },
        socket_pid: socket.transport_pid,
        socket_ip: client_ip,
        queues: []
      }

    Store.add_client client

    if restricted do
      Logger.info "[GATEWAY] Got new RESTRICTED socket #{app_id}:#{client_id} @ #{ip}"
    else
      Logger.info "[GATEWAY] Got new socket #{app_id}:#{client_id} @ #{ip}"
    end
    :ready
    |> Payload.create_payload(%{"client_id" => client_id, "restricted" => restricted})
    |> craft_response(%{app_id: app_id, client_id: client_id, restricted: restricted, encoding: encoding})
  end

  def handle_dispatch(socket, payload) do
    dispatch_type = payload.t
    if Dispatch.can_dispatch?(socket, dispatch_type) do
      processed_payload = process_event_via_pipeline payload, :server
      case processed_payload do
        {:ok, processed} ->
          socket
          |> Dispatch.handle_dispatch(processed)
          |> handle_dispatch_response

        :halted ->
          craft_response []

        {:error, close_payload} ->
          craft_response [close_payload]
      end
    else
      :invalid
      |> Payload.create_payload(%{"error" => "invalid dispatch type #{dispatch_type} (are you restricted?)"})
      |> craft_response
    end
  end

  defp handle_dispatch_response(dispatch_result) do
    case dispatch_result do
      {:ok, %Payload{} = frame} ->
        [frame]
        |> process_outgoing_event
        |> craft_response

      {:ok, {:text, %Payload{}} = frame} ->
        frame
        |> process_outgoing_event
        |> craft_response

      {:ok, frames} when is_list(frames) ->
        frames
        |> process_outgoing_event
        |> craft_response

      {:error, error} ->
        craft_response error
    end
  end

  def process_outgoing_event({:text, %Payload{} = payload}) do
    {:text, process_outgoing_event(payload)}
  end
  def process_outgoing_event(%Payload{} = payload) do
    case process_event_via_pipeline(payload, :client) do
      {:ok, frame} ->
        frame

      :halted ->
        []

      {:error, close_frame} ->
        close_frame
    end
  end
  def process_outgoing_event(payloads) when is_list(payloads) do
    res = Enum.map payloads, &process_outgoing_event/1
    invalid_filter = fn {:text, frame} -> frame.op == @opcodes_name[:invalid] end

    cond do
      Enum.any?(res, &is_nil/1) ->
        []

      Enum.any?(res, invalid_filter) ->
        Enum.filter res, invalid_filter

      true ->
        res
    end
  end

  defp process_event_via_pipeline(%Payload{t: type} = payload, _) when is_nil(type), do: {:ok, payload}
  defp process_event_via_pipeline(%Payload{t: type} = payload, direction) when not is_nil(type) do
    plugins = PluginManager.plugins :all_events
    case plugins do
      [] ->
        {:ok, payload}

      plugins when is_list(plugins) ->
        case run_pipeline(plugins, type, direction, payload, []) do
          {:ok, _frame} = res ->
            res

          :halted ->
            :halted

          {:error, reason, undo_states} ->
            undo_errors =
              undo_states
              # TODO: This should really just append undo states in reverse...
              |> Enum.reverse
              |> unwind_global_undo_stack(direction, type)

            error_payload =
              %{
                reason: reason,
                undo_errors: Enum.map(undo_errors, fn {:error, msg} -> msg end)
              }

            {:error, Payload.close_with_error("Error processing plugin event #{type}", error_payload)}
        end
    end
  end

  # credo:disable-for-next-line
  defp run_pipeline([plugin | rest], event, direction, data, undo_states) do
    case plugin.handle_global_event(event, direction, data) do
      {:next, out_frame, plugin_undo_state} when not is_nil(out_frame) and not is_nil(plugin_undo_state) ->
        out_undo_states = Utils.fast_list_concat undo_states, {plugin, plugin_undo_state}
        run_pipeline rest, event, data, out_frame, out_undo_states

      {:next, out_frame, nil} when not is_nil(out_frame) ->
        run_pipeline rest, event, data, out_frame, undo_states

      {:next, out_frame} when not is_nil(out_frame) ->
        run_pipeline rest, event, data, out_frame, undo_states

      {:halt, _} ->
        # Halts do not return execution to the pipeline, nor do they return any
        # side-effects (read: frames) to the client.
        :halted

      :halt ->
        :halted

      {:error, reason} when is_binary(reason) ->
        {:error, reason, undo_states}

      {:error, reason, plugin_undo_state} when is_binary(reason) and not is_nil(plugin_undo_state) ->
        out_undo_states = Utils.fast_list_concat undo_states, {plugin, plugin_undo_state}
        {:error, reason, out_undo_states}

      {:error, reason, nil} when is_binary(reason) ->
        {:error, reason, undo_states}
    end
  end

  defp run_pipeline([], _event, _direction, payload, _undo_states) do
    {:ok, payload}
  end

  defp unwind_global_undo_stack(undo_states, direction, event) do
    undo_states
    |> Enum.filter(fn {_, state} -> state != nil end)
    |> Enum.map(fn undo_state -> global_undo(undo_state, direction, event) end)
    # We only want the :error tuple results so that we can report them to the
    # client; successful undos don't need to be reported.
    |> Enum.filter(fn res -> res != :ok end)
  end

  defp global_undo({plugin, undo_state}, direction, event) do
    # We don't just take a list of the undo states here, because really we do
    # not want to halt undo when one encounters an error; instead, we want to
    # continue the undo and then report all errors to the client.
    apply plugin, :global_undo, [event, direction, undo_state]
  end

  def handle_heartbeat(socket, _payload) do
    {:ok, client} = Store.get_client socket.assigns[:client_id]
    if client != nil do
      {:ok, _} =
        Store.update_client %{
          client | metadata: Map.put(
              client.metadata,
              Metadata.last_heartbeat_time(),
              Utils.now()
            )
        }

      :heartbeat_ack
      |> Payload.create_payload(%{"client_id" => socket.assigns[:client_id]})
      |> craft_response
    else
      handle_missing_data()
    end
  end

  defp handle_missing_data do
    Payload.close_with_error("payload has no data")
    |> craft_response
  end

  defp handle_invalid_op(_socket, op) do
    Payload.close_with_error("invalid client op #{inspect op}")
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
