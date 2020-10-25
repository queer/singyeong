defmodule Singyeong.QueueTest do
  use Singyeong.QueueCase
  import Phoenix.Socket, only: [assign: 3]
  alias Singyeong.Gateway
  alias Singyeong.Gateway.Dispatch
  alias Singyeong.Gateway.GatewayResponse
  alias Singyeong.Gateway.Payload
  alias Singyeong.Metadata.Query
  alias Singyeong.PluginManager
  alias Singyeong.Queue
  alias Singyeong.Store

  @client_id "client-1"
  @app_id "test-app-1"

  # TODO: Move this setup block somewhere more generic (since it's from dispatch tests)
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

  test "that queuing a message works", %{socket: socket, queue: queue_name} do
    target =
      %Query{
        application: @app_id,
        ops: [],
      }

    {:ok, {:text, out}} =
      Dispatch.handle_dispatch socket, %Payload{
          op: Gateway.opcodes_name()[:dispatch],
          d: %{
            "target" => target,
            "nonce" => nil,
            "payload" => "test!",
            "queue" => queue_name,
          },
          ts: :os.system_time(:millisecond),
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

    {:ok, {:text, _}} =
      Dispatch.handle_dispatch socket, %Payload{
          op: Gateway.opcodes_name()[:dispatch],
          d: %{
            "target" => target,
            "nonce" => nil,
            "payload" => "test!",
            "queue" => queue_name,
          },
          ts: :os.system_time(:millisecond),
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
          d: %{
            "queue" => queue_name,
          },
          ts: :os.system_time(:millisecond),
          t: "QUEUE_REQUEST",
        }

    {:text,
    %Payload{
        d: %{
          "nonce" => nil,
          "payload" => "test!",
        }, op: 4, t: "SEND", ts: _
      }
    } = await_receive_message()
  end

  defp await_receive_message do
    receive do
      msg -> msg
    after
      5000 -> raise "couldn't recv message in time!"
    end
  end
end
