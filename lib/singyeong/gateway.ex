defmodule Singyeong.Gateway do
  alias Singyeong.Gateway.Payload

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

  def heartbeat_interval, do: @heartbeat_interval
  def opcodes_name, do: @opcodes_name
  def opcodes_id, do: @opcodes_id

  defp craft_response(response, assigns \\ %{})
    when (is_tuple(response) or is_list(response)) and is_map(assigns)
    do
    %GatewayResponse{response: response, assigns: assigns}
  end

  def handle_payload(socket, payload) when is_binary(payload) do
    {status, msg} = Poison.decode payload
    case status do
      :ok ->
        handle_payload socket, msg
      _ ->
        Payload.close_with_payload(:invalid, %{"error" => "cannot decode payload"})
    end
  end
  def handle_payload(socket, payload) when is_map(payload) do
    op = payload["op"]
    if not is_nil(op) and is_integer(op) do
      named = @opcodes_id[op]
      case named do
        :identify ->
          # TODO: When a socket IDENTIFYs, we need to assign something to it
          # How to do this?
          handle_identify socket, payload
        :dispatch ->
          # TODO: Real dispatch routing etc
          ""
        :heartbeat ->
          # We only really do heartbeats to keep clients alive.
          # cowboy server will automatically disconnect after some period if
          # no messages come over the socket, so the client is responsible
          # for keeping itself alive.
          handle_heartbeat socket, payload
        _ ->
          handle_invalid_op socket, op
      end
    else
      Payload.close_with_payload(:invalid, %{"error" => "payload has bad opcode"})
      |> craft_response
    end
  end
  def handle_payload(_socket, _payload) do
    Payload.close_with_payload(:invalid, %{"error" => "bad payload"})
    |> craft_response
  end

  defp handle_identify(socket, msg) when is_map(msg) do
    d = msg["d"]
    if not is_nil(d) and is_map(d) do
      client_id = d["client_id"]
      if not is_nil(client_id) and is_binary(client_id) do
        # TODO: Actually do checking of client IDs and shit to ensure validity
        Payload.create_payload(:ready, %{"client_id" => client_id})
        |> craft_response(%{client_id: client_id})
      else
        handle_missing_data()
      end
    else
      handle_missing_data()
    end
  end
  defp handle_dispatch(socket, msg) do
    # TODO: Figure out queueing and shit
  end
  defp handle_heartbeat(socket, msg) do
    d = msg["d"]
    if not is_nil(d) and is_map(d) do
      client_id = d["client_id"]
      if not is_nil(client_id) and is_binary(client_id) do
        # TODO: Update client latency
        Payload.create_payload(:heartbeat_ack, %{"client_id" => socket.assigns[:client_id]})
        |> craft_response
      else
        handle_missing_data()
      end
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
      "heartbeat_interval" => Singyeong.Gateway.heartbeat_interval()
    }
  end
end
