defmodule Singyeong.Metadata.Types do
  @moduledoc """
  The types that 신경 supports for metadata storage. If a type isn't in here,
  then it can't be used for registering metadata, and the client that tries to
  register bad metadata will be disconnected.
  """

  alias Singyeong.Metadata.Type

  @types %{
    "string"  => %Type{typename: :string, validate: &is_binary/1},
    "integer" => %Type{typename: :integer, validate: &is_integer/1},
    "float"   => %Type{typename: :float, validate: &is_float/1},
    "version" => %Type{typename: :version, validate: &Singyeong.Metadata.Types.validate_version/1},
    "list"    => %Type{typename: :list, validate: &Singyeong.Metadata.Types.validate_list/1},
  }

  @spec types() :: %{String.t() => Type.t()}
  def types, do: @types

  @spec type_exists?(String.t()) :: boolean()
  def type_exists?(type), do: Map.has_key? @types, type

  @spec get_type(String.t()) :: Type.t() | nil
  def get_type(type), do: @types[type]

  @spec validate_identity(term()) :: true
  def validate_identity(_), do: true

  @spec validate_version(term()) :: boolean()
  def validate_version(x) do
    is_binary(x) and Version.parse(x) != :error
  end

  @spec validate_list(term()) :: boolean()
  def validate_list(x) do
    is_list x
  end
end
