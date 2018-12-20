defmodule Singyeong.Gateway.Payload do
  alias Singyeong.Gateway

  defstruct op: 0, d: %{}, t: nil

  def to_map(payload) do
    %{
      "op" => payload.op,
      "d" => payload.d,
      "t" => payload.t
    }
  end

  def create_payload(op, data) when is_atom(op) and is_map(data) do
    create_payload Gateway.opcodes_name()[op], data
  end
  def create_payload(op, data) when is_integer(op) and is_map(data) do
    txt = Jason.encode!(%{
      "op"  => op,
      "d"   => data,
      "ts"  => :os.system_time(:millisecond)
    })
    {:text, txt}
  end
  def create_payload(op, data) do
    op_atom = is_atom op
    op_int = is_integer op
    d_map = is_map data
    raise ArgumentError, "bad payload (op_atom = #{op_atom}, op_int = #{op_int}, d_map = #{d_map})"
  end

  def close_with_payload(op, data) do
    [
      create_payload(op, data),
      :close
    ]
  end
end
