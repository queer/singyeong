defmodule Singyeong.DispatchTest do
  use SingyeongWeb.ChannelCase
  alias Singyeong.Gateway
  alias Singyeong.Gateway.Dispatch
  alias Singyeong.Gateway.Payload
  import Phoenix.Socket, only: [assign: 3]

  @client_id "client-1"
  @app_id "test-app-1"

  setup do
    Singyeong.MnesiaStore.initialize()

    socket = socket(SingyeongWeb.Transport.Raw, nil, [client_id: @client_id, app_id: @app_id])

    on_exit "cleanup", fn ->
      Gateway.cleanup socket, @app_id, @client_id
      Singyeong.MnesiaStore.shutdown()
    end

    {:ok, socket: socket}
  end

  test "that SEND dispatch query to a socket works", %{socket: socket} do
    # IDENTIFY with the gateway so that we have everything we need set up
    # This is tested in another location
    Gateway.handle_identify socket, %{
      op: Gateway.opcodes_name()[:identify],
      d: %{
        "client_id" => @client_id,
        "application_id" => @app_id,
        "reconnect" => false,
        "auth" => nil,
        "tags" => ["test", "webscale"]
      },
      ts: :os.system_time(:millisecond),
      t: nil,
    }

    sender = @client_id
    target = %{
      "application" => @app_id,
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
      %Payload{
        d: %{
          "sender" => sender,
          "payload" => payload,
          "nonce" => nonce
        },
        op: op,
        ts: now,
        t: nil,
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
    assert msg.d == expected.d
    assert msg.op == expected.op
    # Really this should be within ~1ms or so, but there's a host of possible
    # things that could make it not work out.
    assert 10 > abs(msg.ts - expected.ts)
  end

  test "that metadata updates work as expected", %{socket: socket} do
    @client_id = "client-1"
    @app_id = "test-app-1"
    socket = assign socket, :app_id, @app_id
    socket = assign socket, :client_id, @client_id
    # IDENTIFY with the gateway so that we have everything we need set up
    # This is tested in another location
    Gateway.handle_identify socket, %Payload{
      op: Gateway.opcodes_name()[:identify],
      d: %{
        "client_id" => @client_id,
        "application_id" => @app_id,
        "reconnect" => false,
        "auth" => nil,
        "tags" => ["test", "webscale"]
      },
      t: nil,
      ts: :os.system_time(:millisecond),
    }

    # Send a fake metadata update and pray
    payload = %Payload{
      t: "UPDATE_METADATA",
      ts: :os.system_time(:millisecond),
      op: Gateway.opcodes_name()[:dispatch],
      d: %{
        "test" => %{
          "type" => "integer",
          "value" => 10
        }
      }
    }
    Dispatch.handle_dispatch socket, payload

    # Wait a little bit and then try to SEND to check that it worked
    Process.sleep 100

    # Actually do and test the dispatch
    sender = @client_id
    target = %{
      "application" => @app_id,
      "optional" => true,
      "ops" => [%{"test" => %{"$eq" => 10}}]
    }
    payload = %{}
    nonce = "1"

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
      %Payload{
        d: %{
          "sender" => sender,
          "payload" => payload,
          "nonce" => nonce
        },
        op: op,
        ts: now,
        t: nil,
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
    assert msg.d == expected.d
    assert msg.op == expected.op
    # Really this should be within ~1ms or so, but there's a host of possible
    # things that could make it not work out.
    assert 10 > abs(msg.ts - expected.ts)
  end
end
