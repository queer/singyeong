defmodule Singyeong.Gateway.Payload.QueueAck do
  @moduledoc false
  use TypedStruct

  typedstruct enforce: true do
    field :queue, String.t()
    field :id, String.t()
  end
end
