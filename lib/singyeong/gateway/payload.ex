defmodule Singyeong.Gateway.Payload do
  @moduledoc """
  Represents the actual JSON (or ETF, msgpack,...) blob that gets sent to a
  client.
  """

  use TypedStruct
  alias Singyeong.{Gateway, Utils}
  alias Singyeong.Gateway.Payload.Error
  alias Singyeong.Metadata.Query

  typedstruct do
    field :op, non_neg_integer(), enforce: true
    field :d, __MODULE__.Dispatch.t() | any(), enforce: true
    field :t, binary() | nil, default: nil
    field :ts, non_neg_integer() | nil, enforce: true
  end

  typedstruct module: Dispatch do
    field :target, Query.t()
    field :nonce, binary() | nil, default: nil
    field :payload, any() | nil
  end

  @spec data_from_json(binary(), map()) :: __MODULE__.Dispatch.t()
  def data_from_json("QUEUE", %{
    "target" => target,
    "queue" => queue,
    "nonce" => nonce,
    "payload" => payload,
  }) do
    %__MODULE__.QueueInsert{
      queue: queue,
      target: Query.json_to_query(target),
      nonce: nonce,
      payload: payload,
    }
  end

  def data_from_json("QUEUE_REQUEST", %{
    "queue" => queue
  }) do
    %__MODULE__.QueueRequest{
      queue: queue
    }
  end

  def data_from_json("QUEUE_REQUEST_CANCEL", %{
    "queue" => queue
  }) do
    %__MODULE__.QueueRequest{
      queue: queue
    }
  end

  def data_from_json("QUEUE_ACK", %{
    "queue" => queue,
    "id" => id,
  }) do
    %__MODULE__.QueueAck{
      queue: queue,
      id: id,
    }
  end

  def data_from_json(_, %{
    "target" => target,
    "payload" => payload,
  } = json) do
    %__MODULE__.Dispatch{
      target: Query.json_to_query(target),
      nonce: json["nonce"],
      payload: payload,
    }
  end

  def data_from_json(_, map), do: map

  def identify_from_json(socket, %{"application_id" => app_id, "client_id" => client_id} = map) do
    %__MODULE__.IdentifyRequest{
      app_id: app_id,
      client_id: client_id,
      auth: map["auth"],
      ip: map["ip"] || socket.assigns[:ip],
      namespace: map["namespace"],
      initial_metadata: map["metadata"],
      receive_client_updates: map["receive_client_updates"] || false,
    }
  end

  @spec from_map(map(), Phoenix.Socket.t()) :: __MODULE__.t()
  def from_map(map, socket) do
    map = Utils.stringify_keys map
    d = map["d"]

    opcode = Gateway.opcodes_id()[map["op"]]
    data =
      case opcode do
        :dispatch ->
          data_from_json map["t"], map["d"]

        :identify ->
          identify_from_json socket, map["d"]

        _ ->
          d
      end

    %__MODULE__{
      op: opcode,
      d: data,
      t: map["t"],
      ts: map["ts"],
    }
  end

  @spec create_payload(op :: atom() | integer(), data :: any()) :: {:text, %__MODULE__{}}
  def create_payload(op, data) when is_atom(op) do
    create_payload Gateway.opcodes_name()[op], data
  end

  def create_payload(op, data) when is_integer(op) do
    create_payload op, nil, data
  end

  def create_payload(op, data) do
    op_atom = is_atom op
    op_int = is_integer op
    d_map = is_map data
    raise ArgumentError, "bad payload (op_atom = #{op_atom}, op_int = #{op_int}, d_map = #{d_map})"
  end

  @spec create_payload(op :: atom() | integer(), t :: binary() | nil, data :: any()) :: {:text, %__MODULE__{}}
  def create_payload(op, t, data) when is_atom(op) do
    create_payload Gateway.opcodes_name()[op], t, data
  end

  def create_payload(op, t, data) when is_integer(op) do
    {:text, %__MODULE__{
      op: op,
      d: data,
      t: t,
      ts: Utils.now(),
    }}
  end

  def create_payload(op, t, data) do
    op_atom = is_atom op
    op_int = is_integer op
    t_bin = is_binary t
    t_nil = is_nil t
    d_map = is_map data
    raise ArgumentError, "bad payload (op_atom = #{op_atom}, op_int = #{op_int}, t_bin = #{t_bin}, t_nil = #{t_nil}, d_map = #{d_map})"
  end

  def error(err, extra_info \\ nil) do
    create_payload :invalid, %Error{error: err, extra_info: extra_info}
  end

  def close_with_payload(op, data) do
    {:close, create_payload(op, data)}
  end

  def close_with_error(err, extra_info \\ nil) do
    close_with_op_and_error :error, err, extra_info
  end

  def close_with_op_and_error(op, err, extra_info \\ nil) do
    {:close, create_payload(op, %Error{error: err, extra_info: extra_info})}
  end

  def to_outgoing(%__MODULE__{op: op, d: data, t: t, ts: ts}) when is_atom(op) do
    %__MODULE__{
      op: Gateway.opcodes_name()[op],
      d: data,
      t: t,
      ts: ts,
    }
  end

  def to_outgoing(%__MODULE__{} = payload) do
    payload
  end
end
