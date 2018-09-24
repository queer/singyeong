defmodule Singyeong.Gateway do
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

  def heartbeat_interval, do: @heartbeat_interval

  def handle_payload(payload) when is_binary(payload) do
    {status, msg} = Poison.decode payload
    case status do
      :ok ->
        handle_payload msg
      _ ->
        close_with_payload(:invalid, %{"error" => "cannot decode payload"})
    end
  end
  def handle_payload(payload) when is_map(payload) do
    op = payload["op"]
    if not is_nil(op) and is_integer(op) do
      named = @opcodes_id[op]
      case named do
        :identify ->
          # TODO: When a socket IDENTIFYs, we need to assign something to it
          # How to do this?
          handle_identify payload
        :dispatch ->
          # TODO: Real dispatch routing etc
          ""
        :heartbeat ->
          # We only really do heartbeats to keep clients alive.
          # cowboy server will automatically disconnect after some period if
          # no messages come over the socket, so the client is responsible
          # for keeping itself alive.
          handle_heartbeat payload
        _ ->
          handle_invalid_op op
      end
    else
      close_with_payload :invalid, %{"error" => "payload has bad opcode"}
    end
  end
  def handle_payload(_payload) do
    close_with_payload :invalid, %{"error" => "bad payload"}
  end

  defp handle_identify(msg) when is_map(msg) do
    d = msg["d"]
    if not is_nil(d) and is_map(d) do
      client_id = d["client_id"]
      if not is_nil(client_id) and is_binary(client_id) do
        # TODO: Actually do checking of client IDs and shit to ensure validity
        {:text, create_payload(:ready, %{"client_id" => client_id})}
      else
        handle_missing_data()
      end
    else
      handle_missing_data()
    end
  end
  defp handle_dispatch(msg) do
    # TODO: Figure out queueing and shit
  end
  defp handle_heartbeat(msg) do
    d = msg["d"]
    if not is_nil(d) and is_map(d) do
      client_id = d["client_id"]
      if not is_nil(client_id) and is_binary(client_id) do
        # TODO: Update client latency
        {:text, create_payload(:heartbeat_ack, %{"client_id" => client_id})}
      else
        handle_missing_data()
      end
    else
      handle_missing_data()
    end
  end
  defp handle_missing_data do
    close_with_payload :invalid, %{"error" => "payload has no data"}
  end
  defp handle_invalid_op(op) do
    close_with_payload :invalid, %{"error" => "invalid client op #{inspect op}"}
  end

  def create_payload(op, data) when is_atom(op) and is_map(data) do
    create_payload @opcodes_name[op], data
  end
  def create_payload(op, data) when is_integer(op) and is_map(data) do
    Poison.encode!(%{
      "op"  => op,
      "d"   => data,
      "ts"  => :os.system_time(:millisecond)
    })
  end
  def create_payload(op, data) do
    op_atom = is_atom op
    op_int = is_integer op
    d_map = is_map data
    raise ArgumentError, "bad payload (op_atom = #{op_atom}, op_int = #{op_int}, d_map = #{d_map})"
  end

  def close_with_payload(op, data) do
    [
      {:text, create_payload(op, data)},
      :close
    ]
  end

  # This is here because we need to be able to send it immediately from
  # user_socket.ex
  def hello do
    %{
      "heartbeat_interval" => Singyeong.Gateway.heartbeat_interval()
    }
  end
end
