defmodule Singyeong.Gateway.Payload.QueueRequest do
  @moduledoc false
  use TypedStruct

  typedstruct enforce: true do
    field :queue, String.t()
  end
end
