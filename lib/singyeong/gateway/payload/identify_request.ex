defmodule Singyeong.Gateway.Payload.IdentifyRequest do
  @moduledoc false

  use TypedStruct

  typedstruct do
    field :client_id, String.t()
    field :app_id, String.t()
    field :ip, String.t() | nil
    field :auth, term() | nil
    field :namespace, String.t() | nil
    field :initial_metadata, map() | nil
  end
end
