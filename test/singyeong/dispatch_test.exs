defmodule Singyeong.DispatchTest do
  use SingyeongWeb.ChannelCase
  alias Singyeong.Gateway
  alias Singyeong.Gateway.Dispatch
  alias Singyeong.Gateway.Payload

  setup do
    Singyeong.MnesiaStore.initialize()

    on_exit "cleanup", fn ->
      Singyeong.MnesiaStore.shutdown()
    end

    {:ok, socket: socket(SingyeongWeb.Transport.Raw, nil, [])}
  end

  test "SEND dispatch query to a socket works", %{socket: socket} do
    # IDENTIFY with the gateway so that we have everything we need set up
    # This is tested in another location
    # Who needs nice TDD anyway amirite :^)
    client_id = "client-1"
    app_id = "test-app-1"
    Gateway.handle_identify socket, %{
      op: Gateway.opcodes_name()[:identify],
      d: %{
        "client_id" => client_id,
        "application_id" => app_id,
        "reconnect" => false,
        "auth" => nil,
        "tags" => ["test", "webscale"]
      },
      t: :os.system_time(:millisecond)
    }

    sender = client_id
    target = %{
      "application" => app_id,
      "optional" => true,
      "ops" => []
    }
    payload = %{}
    nonce = "1"
    # Actually do and test the dispatch
    dispatch =
      %Payload{
        t: "SEND",
        d: %{
          "sender" => sender,
          "target" => target,
          "payload" => payload,
          "nonce" => nonce,
        }
      }

    {:ok, frames} = Dispatch.handle_dispatch socket, dispatch
    now = :os.system_time :millisecond
    op = Gateway.opcodes_name()[:dispatch]
    assert [] == frames
    # TODO: This is marked as unused, I'm not sure why?
    expected = Jason.encode!(%{
        "d" => %{
          "sender" => sender,
          "payload" => payload,
          "nonce" => nonce
        },
        "op" => op,
        "ts" => now
      }
    )
    assert_receive {:text, expected}
  end
end
