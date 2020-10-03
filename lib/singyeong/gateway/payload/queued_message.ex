defmodule Singyeong.Gateway.Payload.QueuedMessage do
  @moduledoc false
  use TypedStruct

  typedstruct do
    field :id, String.t(), enforce: true
    field :queue, String.t(), enforce: true
    field :nonce, String.t() | nil
    field :payload, term()
  end
end
