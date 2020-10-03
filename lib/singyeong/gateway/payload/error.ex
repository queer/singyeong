defmodule Singyeong.Gateway.Payload.Error do
  use TypedStruct

  typedstruct do
    field :error, String.t(), enforce: true
    field :extra_info, term()
  end
end
