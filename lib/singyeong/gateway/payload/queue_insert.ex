defmodule Singyeong.Gateway.Payload.QueueInsert do
  @moduledoc false
  use TypedStruct
  alias Singyeong.Metadata.Query

  typedstruct enforce: true do
    field :queue, String.t()
    field :nonce, String.t()
    field :target, Query.t()
    field :payload, term()
  end
end
