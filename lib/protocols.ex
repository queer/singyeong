require Protocol

defmodule ProtocolsHelper do
  @moduledoc false
  alias Singyeong.Gateway.Payload
  alias Singyeong.Metadata.Query

  @modules [
    Payload,
    Payload.Dispatch,
    Payload.Error,
    Payload.QueueConfirm,
    Payload.QueueDispatch,
    Payload.QueueRequest,
    Payload.QueuedMessage,
    Query,
  ]

  def modules, do: @modules
end

for mod <- ProtocolsHelper.modules() do
  Protocol.derive Jason.Encoder, mod
  Protocol.derive Msgpax.Packer, mod
end
