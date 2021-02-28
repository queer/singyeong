defmodule Singyeong.Gateway do
  @moduledoc """
  The "gateway" into the 신경 system. All messages that a client sends or
  receives over its websocket connection come through the gateway for
  preprocessing, authentication, and other things.
  """

  use TypedStruct
  alias Singyeong.Gateway.{Encoding, Payload}
  alias Singyeong.Gateway.Handler.{DispatchEvent, Heartbeat, Identify}
  alias Singyeong.Metadata
  alias Singyeong.Metadata.UpdateQueue
  alias Singyeong.Queue
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
    # recv
    :error         => 8,
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
    # recv
    8 => :error,
  }

  ## STRUCT DEFINITIONS ##

  typedstruct module: GatewayResponse do
    @moduledoc """
    A packet being sent from the gateway to a client.
    """

    field :response, [] | [Payload.t()] | {:text, Payload.t()} | {:close, {:text, Payload.t()}}, default: []
    field :assigns, map(), default: %{}
  end

  ## HELPERS ##

  @spec heartbeat_interval() :: integer()
  def heartbeat_interval, do: @heartbeat_interval

  @spec opcodes_name() :: %{atom() => integer()}
  def opcodes_name, do: @opcodes_name

  @spec opcodes_id() :: %{integer() => atom()}
  def opcodes_id, do: @opcodes_id

  @spec craft_response(term(), map()) :: GatewayResponse.t()
  def craft_response(response, assigns \\ %{}) when (is_tuple(response) or is_list(response)) and is_map(assigns) do
    %GatewayResponse{response: response, assigns: assigns}
  end

  ## INCOMING PAYLOADS ##

  @spec handle_incoming_payload(Phoenix.Socket.t(), {atom(), binary()}) :: GatewayResponse.t()
  def handle_incoming_payload(socket, {opcode, payload}) when is_atom(opcode) do
    encoding = socket.assigns[:encoding]
    restricted = socket.assigns[:restricted]
    # Decode incoming packets based on the state of the socket

    case Encoding.decode_payload(socket, opcode, payload, encoding, restricted) do
      {:ok, payload} ->
        handle_payload socket, payload

      {:error, msg} ->
        msg
        |> if(do: msg, else: "cannot decode payload")
        |> Payload.close_with_error
        |> craft_response
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
             app_id: ^app_id,
           }} <- Store.get_client(app_id, client_id),
           last_heartbeat when is_integer(last_heartbeat) <- metadata[Metadata.last_heartbeat_time()]
      do
        last_heartbeat + (@heartbeat_interval * 1.5) < Utils.now()
      else
        _ -> false
      end

    if should_disconnect do
      "heartbeat took too long"
      |> Payload.close_with_error
      |> craft_response
    else
      try_handle_event socket, payload
    end
  end

  defp try_handle_event(%Phoenix.Socket{assigns: assigns} = socket, %Payload{op: op} = payload) do
    if op != :identify and assigns[:client_id] == nil do
      # If we don't have a client id assigned, then the client hasn't
      # identified itself yet and as such shouldn't be allowed to do anything
      # BUT identify
      # We try to halt it as soon as possible so that we don't waste time on it
      "sent payload with non-identify opcode without identifying first"
      |> Payload.close_with_error
      |> craft_response
    else
      case op do
        :identify ->
          Identify.handle socket, payload

        :dispatch ->
          DispatchEvent.handle socket, payload

        :heartbeat ->
          # We only really do heartbeats to keep clients alive.
          # The cowboy server will automatically disconnect after some period
          # if no messages come over the socket, so the client is responsible
          # for keeping itself alive.
          Heartbeat.handle socket, payload

        _ ->
          handle_invalid_op socket, op
      end
    end
  rescue
    e ->
      formatted = Exception.format :error, e, __STACKTRACE__
      Logger.error "[GATEWAY] Encountered error handling gateway payload:\n#{formatted}"
      "internal server error"
      |> Payload.close_with_error
      |> craft_response
  end

  ## SOCKET CLOSED ##

  def handle_close(socket) do
    unless is_nil(socket.assigns[:app_id]) and is_nil(socket.assigns[:client_id]) do
      app_id = socket.assigns[:app_id]
      client_id = socket.assigns[:client_id]
      cleanup app_id, client_id
    end
  end

  def cleanup(app_id, client_id) do
    case Store.get_client(app_id, client_id)do
      {:ok, %Client{app_id: ^app_id, client_id: ^client_id} = client} ->
        {:ok, :ok} = Store.remove_client client
        queue_worker = UpdateQueue.name app_id, client_id
        pid = Process.whereis queue_worker

        if pid do
          DynamicSupervisor.terminate_child Singyeong.MetadataQueueSupervisor, pid
        end

        for queue <- client.queues do
          Queue.remove_client queue, {app_id, client_id}
        end

        Logger.info "[GATEWAY] Cleaned up #{app_id}:#{client_id}"

      _ -> nil
    end

  end

  ## OP HANDLING ##

  def handle_missing_data do
    "payload has no data"
    |> Payload.close_with_error
    |> craft_response
  end

  defp handle_invalid_op(_socket, op) do
    "invalid client op #{inspect op}"
    |> Payload.close_with_error
    |> craft_response
  end

  # This is here because we need to be able to send it immediately from the
  # socket transport layer, but it wouldn't really make sense elsewhere.
  def hello, do: %{"heartbeat_interval" => @heartbeat_interval}
end
