defmodule Singyeong.Gateway.Handler do
  @moduledoc """
  A gateway event handler.

      use Singyeong.Gateway.Handler
  """

  alias Phoenix.Socket
  alias Singyeong.Gateway.Payload

  defmacro __using__(_) do
    quote do
      alias Phoenix.Socket
      alias Singyeong.Gateway
      alias Singyeong.Gateway.{Dispatch, Encoding, Payload}
      alias Singyeong.Store
      require Logger

      @behaviour Singyeong.Gateway.Handler
    end
  end

  @callback handle(Socket.t(), Payload.t()) :: term()
end
