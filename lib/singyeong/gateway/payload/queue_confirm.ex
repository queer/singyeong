defmodule Singyeong.Gateway.Payload.QueueConfirm do
  @moduledoc false
  use TypedStruct

  typedstruct enforce: true do
    field :queue, String.t()
  end
end
