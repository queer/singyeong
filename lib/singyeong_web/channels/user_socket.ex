defmodule SingyeongWeb.UserSocket do
  use Phoenix.Socket
  alias Singyeong.Gateway
  alias Singyeong.Gateway.Payload
  alias Singyeong.Gateway.GatewayResponse
  require Logger

  transport :websocket, SingyeongWeb.Transport.RawWs

  # Socket params are passed from the client and can
  # be used to verify and authenticate a user. After
  # verification, you can put default assigns into
  # the socket that will be set for all channels, ie
  #
  #     {:ok, assign(socket, :user_id, verified_user_id)}
  #
  # To deny connection, return `:error`.
  #
  # See `Phoenix.Token` documentation for examples in
  # performing token verification on connect.
  def connect(_params, socket) do
    send self(), Payload.create_payload(:hello, Gateway.hello)
    {:ok, socket}
  end

  # Socket id's are topics that allow you to identify all sockets for a given user:
  #
  #     def id(socket), do: "user_socket:#{socket.assigns.user_id}"
  #
  # Would allow you to broadcast a "disconnect" event and terminate
  # all active sockets and channels for a given user:
  #
  #     SingyeongWeb.Endpoint.broadcast("user_socket:#{user.id}", "disconnect", %{})
  #
  # Returning `nil` makes this socket anonymous.
  def id(_socket), do: nil

  def handle(:text, payload, state) do
    %GatewayResponse{response: response, assigns: assigns} = Gateway.handle_payload state[:socket], payload
    {response, %{state | socket: bulk_assign(state[:socket], assigns)}}
  end

  def handle(:closed, {code, reason}, state) do
    Logger.info "Socket closed with code #{inspect code}: #{inspect reason}"
    {:ok, state}
  end

  defp bulk_assign(socket, assigns) do
    assigns
    |> Map.keys
    |> Enum.reduce(socket, fn(x, acc) ->
        assign(acc, x, assigns[x])
      end)
  end
end
