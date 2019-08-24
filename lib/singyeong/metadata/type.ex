defmodule Singyeong.Metadata.Type do
  @moduledoc """
  A type of metadata, that can be used for strict typing and validation.
  """
  alias Singyeong.Metadata.Types

  @enforce_keys [:typename]
  defstruct typename: nil,
    validation_function: &Types.validate_identity/1
end
