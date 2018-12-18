defmodule Singyeong.Gateway do
  alias Singyeong.Gateway.Payload
  alias Singyeong.Gateway.Dispatch
  alias Singyeong.Metadata.Store
  alias Singyeong.Pubsub

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
  }

  defmodule GatewayResponse do
    # The empty map for response is effectively just a noop
    # If the assigns map isn't empty, everything in it will be assigned to the socket`
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

  def handle_payload(socket, payload) when is_binary(payload) do
    {status, msg} = Jason.decode payload
    case status do
      :ok ->
        handle_payload socket, msg
      _ ->
        Payload.close_with_payload(:invalid, %{"error" => "cannot decode payload"})
        |> craft_response
    end
  end
  def handle_payload(socket, payload) when is_map(payload) do
    should_disconnect =
      unless is_nil(socket.assigns[:app_id]) and is_nil(socket.assigns[:client_id]) do
        # If both are NOT nil, then we need to check last heartbeat
        metadata = Store.get_metadata(socket.assigns[:client_id])
        if Map.has_key?(metadata, "last_heartbeat_time") do
          last_pair = metadata["last_heartbeat_time"]
          if is_map(last_pair) do
            last = last_pair["value"]
            if is_integer(last) do
              last + (@heartbeat_interval * 1.5) < :os.system_time(:millisecond)
            end
          end
        else
          false
        end
      else
        false
      end

    if should_disconnect do
      Payload.close_with_payload(:invalid, %{"error" => "heartbeat took too long"})
      |> craft_response
    else
      #spawn fn ->
      #  send socket.transport_pid, {:text, Jason.encode!(%{"test" => "test"})}
      #end
      op = payload["op"]
      if not is_nil(op) and is_integer(op) do
        try_handle_event socket, payload
      else
        Payload.close_with_payload(:invalid, %{"error" => "payload has bad opcode"})
        |> craft_response
      end
    end
  end
  def handle_payload(_socket, _payload) do
    Payload.close_with_payload(:invalid, %{"error" => "bad payload"})
    |> craft_response
  end

  defp try_handle_event(socket, payload) do
    op = payload["op"]
    named = @opcodes_id[op]
    if named != :identify and is_nil socket.assigns[:client_id] do
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
          Exception.format(:error, e, __STACKTRACE__)
          |> Logger.error
          Payload.close_with_payload(:invalid, %{"error" => "internal server error"})
          |> craft_response
      end
    end
  end

  ## SOCKET CLOSED ##

  def handle_close(socket) do
    unless is_nil(socket.assigns[:client_id]) do
      Pubsub.unregister_socket is_nil(socket.assigns[:client_id])
    end
    unless is_nil(socket.assigns[:app_id]) and is_nil(socket.assigns[:client_id]) do
      Store.remove_client socket.assigns[:app_id], socket.assigns[:client_id]
    end
  end

  ## OP HANDLING ##

  defp handle_identify(socket, msg) when is_map(msg) do
    d = msg["d"]
    if not is_nil(d) and is_map(d) do
      client_id = d["client_id"]
      app_id = d["application_id"]
      if not is_nil(client_id) and is_binary(client_id)
        and not is_nil(app_id) and is_binary(app_id) do
        # Check app/client IDs to ensure validity
        case Store.store_has_client?(app_id, client_id) do
          {:ok, 0} ->
            # Client doesn't exist, add to store and okay it
            Store.add_client_to_store app_id, client_id
            Pubsub.register_socket client_id, socket
            Logger.info "Got new socket for #{app_id}: #{client_id}"
            Payload.create_payload(:ready, %{"client_id" => client_id})
            |> craft_response(%{client_id: client_id, app_id: app_id})
          {:ok, _} ->
            if d["reconnect"] do
              # Client does exist, but this is a reconnect, so add to store and okay it
              Store.add_client_to_store app_id, client_id
              Pubsub.register_socket client_id, socket
              Logger.info "Got new socket for #{app_id}: #{client_id}"
              Payload.create_payload(:ready, %{"client_id" => client_id})
              |> craft_response(%{client_id: client_id, app_id: app_id})
            else
              # If we already have a client, reject outright
              Payload.close_with_payload(:invalid, %{"error" => "client id #{client_id} already registered for application id #{app_id}"})
              |> craft_response
            end
          {:error, e} ->
            Payload.close_with_payload(:invalid, %{"error" => "#{inspect e, pretty: true}"})
            |> craft_response
        end
      else
        handle_missing_data()
      end
    else
      handle_missing_data()
    end
  end

  defp handle_dispatch(socket, msg) do
    res = Dispatch.handle_dispatch socket, msg
    case res do
      {:ok, frames} ->
        frames
        |> craft_response
      {:error, error} ->
        error
        |> craft_response
    end
  end

  defp handle_heartbeat(socket, _msg) do
    client_id = socket.assigns[:client_id]
    if not is_nil(client_id) and is_binary(client_id) do
      # When we ack the heartbeat, update last heartbeat time
      Store.update_metadata %{"last_heartbeat_time" => %{"type" => "integer", "value" => :os.system_time(:millisecond)}}, socket.assigns[:client_id]
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
  # user_socket.ex
  def hello do
    %{
      "heartbeat_interval" => @heartbeat_interval
    }
  end
end
