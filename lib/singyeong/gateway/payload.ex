defmodule Singyeong.Gateway.Payload do
  alias Singyeong.Gateway

  @type t :: %__MODULE__{op: integer(), d: map(), t: binary() | nil}

  defstruct op: 0, d: %{}, t: nil

  def create_payload(op, data) when is_atom(op) and is_map(data) do
    create_payload Gateway.opcodes_name()[op], data
  end
  def create_payload(op, data) when is_integer(op) and is_map(data) do
    txt =
      %{
        "op"  => op,
        "d"   => data,
        "ts"  => :os.system_time(:millisecond)
      }
      #Jason.encode!(%{
      #  "op"  => op,
      #  "d"   => data,
      #  "ts"  => :os.system_time(:millisecond)
      #})
    {:text, txt}
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
