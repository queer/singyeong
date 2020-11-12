defmodule Singyeong.Gateway.Payload.QueueDispatch do
  @moduledoc false
  use TypedStruct

  typedstruct enforce: true do
    field :queue, String.t()
    field :payload, term()
    field :id, String.t()
  end
end
