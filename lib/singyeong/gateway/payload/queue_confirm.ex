defmodule Singyeong.Gateway.Payload.QueueConfirm do
  use TypedStruct

  typedstruct do
    field :queue, String.t(), enforce: true
  end
end
