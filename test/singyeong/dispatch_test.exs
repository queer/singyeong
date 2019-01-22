defmodule Singyeong.DispatchTest do
  use SingyeongWeb.ChannelCase

  setup do
    {:ok, socket: socket()}
  end

  test "dispatch query to a socket works", %{socket: socket} do
    #IO.inspect socket, pretty: true
    assert true
  end
end
