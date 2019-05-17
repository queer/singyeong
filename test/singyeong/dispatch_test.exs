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

  test "that SEND dispatch query to a socket works", %{socket: socket} do
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
    expected =
      %{
        "d" => %{
          "sender" => sender,
          "payload" => payload,
          "nonce" => nonce
        },
        "op" => op,
        "ts" => now,
      }

    Process.sleep 100
    # assert_receive / assert_received exist, but we have the issue that
    # waiting for a message to be received may actually take longer than 1ms -
    # especially if we "send" the initial message near the end of a millisecond
    # - meaning that we could have timestamp variance between the expected
    # ts and the ts that the gateway sends back. We can get around this by
    # pulling the message from the process' mailbox ourselves, and do the
    # "pattern matching" manually with == instead of doing a real pattern
    # match.
    {:messages, msgs} = :erlang.process_info self(), :messages
    {opcode, msg} = hd msgs
    assert :text == opcode
    assert msg["d"] == expected["d"]
    assert msg["op"] == expected["op"]
    # Really this should be within ~1ms or so, but there's a host of possible
    # things that could make it not work out.
    assert 10 > abs(msg["ts"] - expected["ts"])
  end
end
