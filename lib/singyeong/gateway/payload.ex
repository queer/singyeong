defmodule Singyeong.Gateway.Payload do
  @moduledoc """
  Represents actual JSON (or ETF, msgpack,...) blob that gets sent to a client.
  """

  alias Singyeong.Gateway

  @type t :: %__MODULE__{op: integer(), d: any(), t: binary() | nil, ts: number() | nil}

  defstruct op: 0, d: %{}, t: nil, ts: 0

  @spec create_payload(op :: atom() | integer(), data :: any()) :: {:text, %__MODULE__{}}
  def create_payload(op, data) when is_atom(op) do
    create_payload Gateway.opcodes_name()[op], data
  end
  def create_payload(op, data) when is_integer(op) do
    {:text, %__MODULE__{
        op: op,
        d: data,
        t: nil,
        ts: :os.system_time(:millisecond),
      }
    }
  end
  def create_payload(op, data) do
    op_atom = is_atom op
    op_int = is_integer op
    d_map = is_map data
    raise ArgumentError, "bad payload (op_atom = #{op_atom}, op_int = #{op_int}, d_map = #{d_map})"
  end

  def close_with_payload(op, data) do
    {:close, create_payload(op, data)}
  end
end
