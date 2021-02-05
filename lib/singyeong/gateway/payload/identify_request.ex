defmodule Singyeong.Gateway.Payload.IdentifyRequest do
  use TypedStruct

  typedstruct do
    field :client_id, String.t()
    field :app_id, String.t()
    field :ip, String.t() | nil
    field :auth, term() | nil
  end
end
