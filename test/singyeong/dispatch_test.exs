defmodule Singyeong.DispatchTest do
  # use SingyeongWeb.ChannelCase
  use Singyeong.DispatchCase
  import Phoenix.Socket, only: [assign: 3]
  alias Singyeong.Gateway
  alias Singyeong.Gateway.Dispatch
  alias Singyeong.Gateway.GatewayResponse
  alias Singyeong.Gateway.Handler.DispatchEvent
  alias Singyeong.Gateway.Payload
  alias Singyeong.Metadata.Query
  alias Singyeong.Store
  alias Singyeong.Utils

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
        ts: Utils.now(),
      }

    {:ok, frames} = Dispatch.handle_dispatch socket, dispatch
    now = Utils.now()
    assert [] == frames
    expected =
      %Payload{
        op: 4,
        d: %Payload.Dispatch{
          payload: payload,
          nonce: nonce,
          target: nil,
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
        ts: Utils.now(),
      }

    {:ok, frames} = Dispatch.handle_dispatch socket, dispatch
    now = Utils.now()
    assert [] == frames
    expected =
      %Payload{
        op: 4,
        d: %Payload.Dispatch{
          payload: payload,
          nonce: nonce,
          target: nil,
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
      ts: Utils.now(),
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
    Process.sleep 200

    # Actually do and test the dispatch
    target = Query.json_to_query %{
      "application" => @app_id,
      "optional" => true,
      "ops" => [
        %{
          "path" => "/test",
          "op" => "$eq",
          "to" => %{"value" => 10}
        },
      ],
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
        ts: Utils.now()
      }

    {:ok, frames} = Dispatch.handle_dispatch socket, dispatch
    now = Utils.now()
    assert [] == frames
    expected =
      %Payload{
        op: 4,
        d: %Payload.Dispatch{
          payload: payload,
          nonce: nonce,
          target: nil,
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
        ts: Utils.now(),
      }

    %GatewayResponse{assigns: %{}, response: frames} = DispatchEvent.handle socket, dispatch
    now = Utils.now()
    assert [] == frames
    expected =
      %Payload{
        op: 4,
        d: %Payload.Dispatch{
          payload: payload,
          nonce: nonce,
          target: nil,
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
  test "that list queries work as expected", %{socket: socket} do
    # Send a fake metadata update and pray
    payload = %Payload{
      t: "UPDATE_METADATA",
      ts: Utils.now(),
      op: 4,
      d: %{
        "test" => %{
          "type" => "list",
          "value" => [1, 2, 3, 4, 5],
        }
      }
    }
    Dispatch.handle_dispatch socket, payload

    # Wait a little bit and then try to SEND to check that it worked
    Process.sleep 200

    # Actually do and test the dispatch
    target = Query.json_to_query %{
      "application" => @app_id,
      "optional" => true,
      "ops" => [
        %{
          "path" => "/test",
          "op" => "$contains",
          "to" => %{"value" => 1}
        },
      ],
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
        ts: Utils.now()
      }

    {:ok, frames} = Dispatch.handle_dispatch socket, dispatch
    now = Utils.now()
    assert [] == frames
    expected =
      %Payload{
        op: 4,
        d: %Payload.Dispatch{
          payload: payload,
          nonce: nonce,
          target: nil,
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
  test "that list queries work as expected with paths", %{socket: socket} do
    # Send a fake metadata update and pray
    payload = %Payload{
      t: "UPDATE_METADATA",
      ts: Utils.now(),
      op: 4,
      d: %{
        "test" => %{
          "type" => "list",
          "value" => [1, 2, 3, 4, 5],
        }
      }
    }
    Dispatch.handle_dispatch socket, payload

    # Wait a little bit and then try to SEND to check that it worked
    Process.sleep 200

    # Actually do and test the dispatch
    target = Query.json_to_query %{
      "application" => @app_id,
      "optional" => true,
      "ops" => [
        %{
          "path" => "/test/0",
          "op" => "$eq",
          "to" => %{"value" => 1},
        },
      ],
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
        ts: Utils.now()
      }

    {:ok, frames} = Dispatch.handle_dispatch socket, dispatch
    now = Utils.now()
    assert [] == frames
    expected =
      %Payload{
        op: 4,
        d: %Payload.Dispatch{
          payload: payload,
          nonce: nonce,
          target: nil,
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
  test "that map queries work as expected with paths", %{socket: socket} do
    # Send a fake metadata update and pray
    payload = %Payload{
      t: "UPDATE_METADATA",
      ts: Utils.now(),
      op: 4,
      d: %{
        "test" => %{
          "type" => "map",
          "value" => %{"key" => [1, 2, 3, 4, 5]},
        },
      },
    }
    Dispatch.handle_dispatch socket, payload

    # Wait a little bit and then try to SEND to check that it worked
    Process.sleep 200

    # Actually do and test the dispatch
    target = Query.json_to_query %{
      "application" => @app_id,
      "optional" => true,
      "ops" => [
        %{
          "path" => "/test/key/0",
          "op" => "$eq",
          "to" => %{"value" => 1},
        },
      ],
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
        ts: Utils.now()
      }

    {:ok, frames} = Dispatch.handle_dispatch socket, dispatch
    now = Utils.now()
    assert [] == frames
    expected =
      %Payload{
        op: 4,
        d: %Payload.Dispatch{
          payload: payload,
          nonce: nonce,
          target: nil,
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

  test "that logical ops work as expected", %{socket: socket} do
    # Send a fake metadata update and pray
    payload = %Payload{
      t: "UPDATE_METADATA",
      ts: Utils.now(),
      op: 4,
      d: %{
        "test" => %{
          "type" => "integer",
          "value" => 15,
        }
      }
    }
    Dispatch.handle_dispatch socket, payload

    # Wait a little bit and then try to SEND to check that it worked
    Process.sleep 200

    # Actually do and test the dispatch
    target = Query.json_to_query %{
      "application" => @app_id,
      "optional" => true,
      "ops" => [
        %{
          "op" => "$and",
          "with" => [
            %{
              "path" => "/test",
              "op" => "$gt",
              "to" => %{"value" => 10}
            },
            %{
              "path" => "/test",
              "op" => "$lt",
              "to" => %{"value" => 20}
            },
          ]
        }
      ],
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
        ts: Utils.now()
      }

    {:ok, frames} = Dispatch.handle_dispatch socket, dispatch
    now = Utils.now()
    assert [] == frames
    expected =
      %Payload{
        op: 4,
        d: %Payload.Dispatch{
          payload: payload,
          nonce: nonce,
          target: nil,
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

  test "that selectors work as expected", %{socket: socket} do
    # Send a fake metadata update and pray
    payload = %Payload{
      t: "UPDATE_METADATA",
      ts: Utils.now(),
      op: 4,
      d: %{
        "test" => %{
          "type" => "integer",
          "value" => 1,
        }
      }
    }
    Dispatch.handle_dispatch socket, payload

    # Wait a little bit and then try to SEND to check that it worked
    Process.sleep 200

    # Actually do and test the dispatch
    target = Query.json_to_query %{
      "application" => @app_id,
      "optional" => true,
      "ops" => [
        %{
          "path" => "/test",
          "op" => "$eq",
          "to" => %{"value" => 1}
        },
      ],
      "selector" => %{"$min" => "test"},
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
        ts: Utils.now()
      }

    {:ok, frames} = Dispatch.handle_dispatch socket, dispatch
    now = Utils.now()
    assert [] == frames
    expected =
      %Payload{
        op: 4,
        d: %Payload.Dispatch{
          payload: payload,
          nonce: nonce,
          target: nil,
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
