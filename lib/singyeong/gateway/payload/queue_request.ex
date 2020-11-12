defmodule Singyeong.Gateway.Payload.QueueRequest do
  @moduledoc false
  use TypedStruct

  typedstruct do
    field :queue, String.t(), enforce: true
  end
end
