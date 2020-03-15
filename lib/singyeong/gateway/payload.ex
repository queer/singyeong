defmodule Singyeong.Gateway.Payload do
  @moduledoc """
  Represents actual JSON (or ETF, msgpack,...) blob that gets sent to a client.
  """

  alias Singyeong.Gateway

  @type t :: %__MODULE__{op: integer(), d: any(), t: binary() | nil, ts: number() | nil}

  defstruct op: -1, d: %{}, t: nil, ts: -1

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
end
