defmodule Singyeong.Metadata.Type do
  alias Singyeong.Metadata.Types

  @enforce_keys [:typename]
  defstruct typename: nil,
    validation_function: &Types.validate_identity/1
end
