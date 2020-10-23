defmodule Singyeong.Gateway.Payload.QueuedMessage do
  @moduledoc false
  use TypedStruct
  alias Singyeong.Metadata.Query

  typedstruct do
    field :id, String.t()
    field :queue, String.t(), enforce: true
    field :nonce, String.t() | nil
    field :target, Query.t(), enforce: true
    field :payload, term(), enforce: true
  end
end
