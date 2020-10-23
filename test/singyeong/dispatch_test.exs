defmodule Singyeong.DispatchTest do
  use SingyeongWeb.ChannelCase
  import Phoenix.Socket, only: [assign: 3]
  alias Singyeong.Gateway
  alias Singyeong.Gateway.Dispatch
  alias Singyeong.Gateway.GatewayResponse
  alias Singyeong.Gateway.Payload
  alias Singyeong.Metadata.Query
  alias Singyeong.PluginManager
  alias Singyeong.Store

  @client_id "client-1"
  @app_id "test-app-1"

  setup do
    Store.start()
    PluginManager.init()

    socket = socket SingyeongWeb.Transport.Raw, nil, [client_id: @client_id, app_id: @app_id]

    # IDENTIFY with the gateway so that we have everything we need set up
    # This is tested in gateway_test.exs
    %GatewayResponse{assigns: assigns} =
      Gateway.handle_identify socket, %Payload{
        op: Gateway.opcodes_name()[:identify],
        d: %{
          "client_id" => @client_id,
          "application_id" => @app_id,
          "auth" => nil,
        },
        ts: :os.system_time(:millisecond),
        t: nil,
      }

    socket =
      assigns
      |> Map.keys
      |> Enum.reduce(socket, fn(x, acc) ->
        assign acc, x, assigns[x]
      end)

    on_exit "cleanup", fn ->
      Gateway.cleanup @app_id, @client_id
      Store.stop()
    end

    {:ok, socket: socket}
  end

  @tag capture_log: true
  test "that SEND dispatch query to a socket works", %{socket: socket} do
    target = Query.json_to_query %{
      "application" => @app_id,
      "optional" => true,
      "ops" => []
    }
    payload = %{}
    nonce = "1"
    # Actually do and test the dispatch
    dispatch =
      %Payload{
        op: 4,
        t: "SEND",
        d: %Payload.Dispatch{
          target: target,
          payload: payload,
          nonce: nonce,
        },
        ts: :os.system_time(:millisecond),
      }

    {:ok, frames} = Dispatch.handle_dispatch socket, dispatch
    now = :os.system_time :millisecond
    assert [] == frames
    expected =
      %Payload{
        op: 4,
        d: %{
          "payload" => payload,
          "nonce" => nonce
        },
        ts: now,
        t: "SEND",
      }

    {opcode, msg} = await_receive_message()
    assert :text == opcode
    assert expected.d == msg.d
    assert expected.op == msg.op
    assert expected.t == msg.t
    # Really this should be within ~1ms or so, but there's a host of possible
    # things that could make it not work out.
    assert 10 > abs(msg.ts - expected.ts)
  end

  @tag capture_log: true
  test "that SEND with nil ops in the query works as expected", %{socket: socket} do
    target = Query.json_to_query %{
      "application" => @app_id,
      "optional" => true,
      "ops" => nil
    }
    payload = %{}
    nonce = "1"
    # Actually do and test the dispatch
    dispatch =
      %Payload{
        op: 4,
        t: "SEND",
        d: %Payload.Dispatch{
          target: target,
          payload: payload,
          nonce: nonce,
        },
        ts: :os.system_time(:millisecond),
      }

    {:ok, frames} = Dispatch.handle_dispatch socket, dispatch
    now = :os.system_time :millisecond
    assert [] == frames
    expected =
      %Payload{
        op: 4,
        d: %{
          "payload" => payload,
          "nonce" => nonce
        },
        ts: now,
        t: "SEND",
      }

    {opcode, msg} = await_receive_message()
    assert :text == opcode
    assert expected.d == msg.d
    assert expected.op == msg.op
    assert expected.t == msg.t
    assert 10 > abs(msg.ts - expected.ts)
  end

  @tag capture_log: true
  test "that metadata updates work as expected", %{socket: socket} do
    # Send a fake metadata update and pray
    payload = %Payload{
      t: "UPDATE_METADATA",
      ts: :os.system_time(:millisecond),
      op: 4,
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
    target = Query.json_to_query %{
      "application" => @app_id,
      "optional" => true,
      "ops" => [%{"test" => %{"$eq" => 10}}]
    }
    payload = %{}
    nonce = "1"

    dispatch =
      %Payload{
        op: 4,
        t: "SEND",
        d: %Payload.Dispatch{
          target: target,
          payload: payload,
          nonce: nonce,
        },
        ts: :os.system_time(:millisecond)
      }

    {:ok, frames} = Dispatch.handle_dispatch socket, dispatch
    now = :os.system_time :millisecond
    assert [] == frames
    expected =
      %Payload{
        op: 4,
        d: %{
          "payload" => payload,
          "nonce" => nonce,
        },
        ts: now,
        t: "SEND",
      }

    {opcode, msg} = await_receive_message()
    assert :text == opcode
    assert expected.d == msg.d
    assert expected.op == msg.op
    assert expected.t == msg.t
    assert 10 > abs(msg.ts - expected.ts)
  end

  @tag capture_log: true
  test "that dispatch via `Gateway.handle_dispatch` works as expected", %{socket: socket} do
    target = Query.json_to_query %{
      "application" => @app_id,
      "optional" => true,
      "ops" => nil
    }
    payload = %{}
    nonce = "1"
    # Actually do and test the dispatch
    dispatch =
      %Payload{
        op: 4,
        t: "SEND",
        d: %Payload.Dispatch{
          target: target,
          payload: payload,
          nonce: nonce,
        },
        ts: :os.system_time(:millisecond),
      }

    %GatewayResponse{assigns: %{}, response: frames} = Gateway.handle_dispatch socket, dispatch
    now = :os.system_time :millisecond
    assert [] == frames
    expected =
      %Payload{
        op: 4,
        d: %{
          "payload" => payload,
          "nonce" => nonce,
        },
        ts: now,
        t: "SEND",
      }

    {opcode, msg} = await_receive_message()
    assert :text == opcode
    assert expected.d == msg.d
    assert expected.op == msg.op
    assert expected.t == msg.t
    assert 10 > abs(msg.ts - expected.ts)
  end

  defp await_receive_message do
    # assert_receive / assert_received exist, but we have the issue that
    # waiting for a message to be received may actually take longer than 1ms -
    # especially if we "send" the initial message near the end of a millisecond
    # - meaning that we could have timestamp variance between the expected
    # ts and the ts that the gateway sends back. We can get around this by
    # pulling the message from the process' mailbox ourselves, and do the
    # "pattern matching" manually with == instead of doing a real pattern
    # match.
    receive do
      msg -> msg
    after
      5000 -> raise "couldn't recv message in time!"
    end
  end
end
