require Protocol

defmodule ProtocolsHelper do
  @moduledoc false

  @modules [
    Singyeong.Gateway.Payload,
    Singyeong.Gateway.Payload.Error,
    Singyeong.Gateway.Payload.QueueConfirm,
    Singyeong.Gateway.Payload.QueuedMessage,
  ]

  def modules, do: @modules
end

for mod <- ProtocolsHelper.modules() do
  Protocol.derive Jason.Encoder, mod
  Protocol.derive Msgpax.Packer, mod
end
