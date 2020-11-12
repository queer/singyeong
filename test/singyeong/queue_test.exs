defmodule Singyeong.QueueTest do
  use Singyeong.DispatchCase
  use Singyeong.QueueCase
  import Phoenix.Socket, only: [assign: 3]
  alias Singyeong.Config
  alias Singyeong.Gateway
  alias Singyeong.Gateway.Dispatch
  alias Singyeong.Gateway.GatewayResponse
  alias Singyeong.Gateway.Payload
  alias Singyeong.Gateway.Payload.{
    QueueConfirm,
    QueueDispatch,
    QueueInsert,
    QueueRequest,
  }
  alias Singyeong.Metadata.Query
  alias Singyeong.PluginManager
  alias Singyeong.Queue
  alias Singyeong.Store
  alias Singyeong.Utils

  @app_id "test-app-1"

  test "that queuing a message works", %{socket: socket, queue: queue_name} do
    target =
      %Query{
        application: @app_id,
        ops: [],
      }

    {:ok, {:text, out}} =
      Dispatch.handle_dispatch socket, %Payload{
          op: Gateway.opcodes_name()[:dispatch],
          d: %QueueInsert{
            target: target,
            nonce: nil,
            payload: "test!",
            queue: queue_name,
          },
          ts: Utils.now(),
          t: "QUEUE",
        }

    assert %Payload{
      d: %Payload.QueueConfirm{
        queue: ^queue_name,
      }
    } = out

    assert {:ok, 1} == Queue.len(queue_name)
    assert_queued queue_name, %Payload.QueuedMessage{
      nonce: nil,
      payload: "test!",
      target: ^target,
      queue: ^queue_name,
    }
  end

  test "that requesting a message works", %{socket: socket, queue: queue_name} do
    target =
      %Query{
        application: @app_id,
        ops: [],
      }

    {:ok,
      {:text,
        %Payload {
          op: 4,
          t: "QUEUE_CONFIRM",
          ts: _,
          d: %QueueConfirm{
            queue: ^queue_name,
          }
    }}} =
      Dispatch.handle_dispatch socket, %Payload{
          op: Gateway.opcodes_name()[:dispatch],
          d: %QueueInsert{
            target: target,
            nonce: nil,
            payload: "test!",
            queue: queue_name,
          },
          ts: Utils.now(),
          t: "QUEUE",
        }

    assert_queued queue_name, %Payload.QueuedMessage{
      payload: "test!",
      target: ^target,
      queue: ^queue_name,
    }

    {:ok, []} =
      Dispatch.handle_dispatch socket, %Payload{
          op: Gateway.opcodes_name()[:dispatch],
          d: %QueueRequest{
            queue: queue_name,
          },
          ts: Utils.now(),
          t: "QUEUE_REQUEST",
        }

    {:text, %Payload{
        d: %Payload.Dispatch{
          nonce: nil,
          payload: %QueueDispatch{
            payload: "test!",
            queue: ^queue_name,
          },
        },
        op: 4,
        t: "SEND",
        ts: _,
      }
    } = await_receive_message()
  end

  test "that an unresolveable message DLQs and requeues", %{socket: socket, queue: queue_name} do
    target =
      %Query{
        application: "unresolveable-app-name",
        ops: [],
      }

    {:ok,
      {:text,
        %Payload {
          op: 4,
          t: "QUEUE_CONFIRM",
          ts: _,
          d: %QueueConfirm{
            queue: ^queue_name,
          }
    }}} =
      Dispatch.handle_dispatch socket, %Payload{
          op: Gateway.opcodes_name()[:dispatch],
          d: %QueueInsert{
            target: target,
            nonce: nil,
            payload: "test!",
            queue: queue_name,
          },
          ts: Utils.now(),
          t: "QUEUE",
        }

    # Since there's no pending clients yet, this message doesn't instantly DLQ,
    # so we can assert it's in the queue.
    assert_queued queue_name, %Payload.QueuedMessage{
      payload: "test!",
      target: ^target,
      queue: ^queue_name,
    }

    refute_dlq queue_name, %Payload.QueuedMessage{
      payload: "test!",
      target: ^target,
      queue: ^queue_name,
    }

    # Register ourselves to receive a message. This will effectively force the
    # queue to dispense a message, but it can't be delivered, so...
    {:ok, []} =
      Dispatch.handle_dispatch socket, %Payload{
          op: Gateway.opcodes_name()[:dispatch],
          d: %QueueRequest{
            queue: queue_name,
          },
          ts: Utils.now(),
          t: "QUEUE_REQUEST",
        }

    # ...Now that we've registered that we want a message...

    # ...The message that we couldn't route immediately got DLQ'd.
    assert_dlq queue_name, %Payload.QueuedMessage{
      payload: "test!",
      target: ^target,
      queue: ^queue_name,
    }

    refute_queued queue_name, %Payload.QueuedMessage{
      payload: "test!",
      target: ^target,
      queue: ^queue_name,
    }

    # And once we wait a little bit...
    :timer.sleep Config.queue_dlq_time() * 2

    # ...It's right back in the queue, no longer in the DLQ
    assert_queued queue_name, %Payload.QueuedMessage{
      payload: "test!",
      target: ^target,
      queue: ^queue_name,
    }

    refute_dlq queue_name, %Payload.QueuedMessage{
      payload: "test!",
      target: ^target,
      queue: ^queue_name,
    }
  end

  test "that an unACKed message DLQs and requeues", %{socket: socket, queue: queue_name} do
    target =
      %Query{
        application: @app_id,
        ops: [],
      }

    # Queue up a message to be sent, and ensure it's confirmed.
    {:ok,
      {:text,
        %Payload {
          op: 4,
          t: "QUEUE_CONFIRM",
          ts: _,
          d: %QueueConfirm{
            queue: ^queue_name,
          }
    }}} =
      Dispatch.handle_dispatch socket, %Payload{
          op: Gateway.opcodes_name()[:dispatch],
          d: %QueueInsert{
            target: target,
            nonce: nil,
            payload: "test!",
            queue: queue_name,
          },
          ts: Utils.now(),
          t: "QUEUE",
        }

    # It should be impossible for this to fail.
    {:ok, empty?} = Queue.is_empty?(queue_name)
    refute empty?

    # Once we've done that, this message should be queued. Also should be
    # impossible for this to fail.
    assert_queued queue_name, %Payload.QueuedMessage{
      payload: "test!",
      target: ^target,
      queue: ^queue_name,
    }

    # Request a message and receive back nothing initially. This is because the
    # queue has to run a cluster-wide query and all that.
    {:ok, []} =
      Dispatch.handle_dispatch socket, %Payload{
          op: Gateway.opcodes_name()[:dispatch],
          d: %QueueRequest{
            queue: queue_name,
          },
          ts: Utils.now(),
          t: "QUEUE_REQUEST",
        }

    # Assert that we received the message...
    {:text, %Payload{
        d: %Payload.Dispatch{
          nonce: nil,
          payload: %QueueDispatch{
            payload: "test!",
            queue: ^queue_name,
            id: id,
          },
        },
        op: 4,
        t: "SEND",
        ts: _,
      }
    } = await_receive_message()

    # ...And assert that the queue is now empty...
    {:ok, empty?} = Queue.is_empty?(queue_name)
    assert empty?

    # ...But also assert that the message is pending an ack.
    assert_ack queue_name, id, %Payload.QueuedMessage{
      payload: "test!",
      target: ^target,
      queue: ^queue_name,
    }

    # Then wait for the ack to time out...
    :timer.sleep Config.queue_ack_timeout() * 2
    # ...And ensure it's in the DLQ.
    assert_dlq queue_name, %Payload.QueuedMessage{
      payload: "test!",
      target: ^target,
      queue: ^queue_name,
    }

    # Then wait for the DLQ to time out...
    :timer.sleep Config.queue_dlq_time() * 2
    # ...And assert it's back in the queue.
    assert_queued queue_name, %Payload.QueuedMessage{
      payload: "test!",
      target: ^target,
      queue: ^queue_name,
    }
  end

  defp await_receive_message do
    receive do
      msg -> msg
    after
      5000 -> raise "couldn't recv message in time!"
    end
  end
end
