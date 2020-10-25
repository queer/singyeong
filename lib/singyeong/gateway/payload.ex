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

  @spec dispatch_from_json(binary(), map()) :: __MODULE__.Dispatch.t()
  def dispatch_from_json("QUEUE", %{"target" => target} = map) do
    %{map | "target" => Query.json_to_query(target)}
  end
  def dispatch_from_json("QUEUE", map), do: map

  def dispatch_from_json(type, %{
    "target" => target,
    "nonce" => nonce,
    "payload" => payload,
  }) do
    %__MODULE__.Dispatch{
      target: Query.json_to_query(target),
      nonce: nonce,
      payload: payload,
    }
  end

  @spec from_map(map()) :: __MODULE__.t()
  def from_map(map) when is_map(map) do
    map = Utils.stringify_keys map
    %__MODULE__{
      op: map["op"],
      d: map["d"],
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
      ts: :os.system_time(:millisecond)
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

  def close_with_payload(op, data) do
    {:close, create_payload(op, data)}
  end

  def close_with_error(err, extra_info \\ nil) do
    close_with_op_and_error :invalid, err, extra_info
  end

  def close_with_op_and_error(op, err, extra_info \\ nil) do
    {:close, create_payload(op, %Error{error: err, extra_info: extra_info})}
  end
end
