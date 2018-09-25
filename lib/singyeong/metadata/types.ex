defmodule Singyeong.Metadata.Types do
  @moduledoc """
  The types that 신경 supports for metadata storage. If a type isn't in here,
  then it can't be used for registering metadata, and the client that tries to
  register bad metadata will be disconnected.
  """

  alias Singyeong.Metadata.Type

  @types %{
    string: %Type{typename: :string, validation_function: &is_binary/1},
    integer: %Type{typename: :integer, validation_function: &is_integer/1},
    float: %Type{typename: :float, validation_function: &is_float/1},
    version: %Type{typename: :version, validation_function: &Types.validate_version/1},
  }

  def types, do: @types

  def validate_identity(_), do: true

  def validate_version(x) do
    is_binary(x) and Version.parse(x) != :error
  end
end
