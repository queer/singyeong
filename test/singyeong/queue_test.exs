defmodule Singyeong.QueueTest do
  use Singyeong.QueueCase
  import Phoenix.Socket, only: [assign: 3]
  alias Singyeong.Gateway
  alias Singyeong.Gateway.Dispatch
  alias Singyeong.Gateway.GatewayResponse
  alias Singyeong.Gateway.Payload
  alias Singyeong.PluginManager
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

  test "that queuing a message works", %{socket: socket} do
    target = %{
      "application" => @app_id,
      "ops" => [],
    }
    Dispatch.handle_dispatch socket, %Payload{
      op: Gateway.opcodes_name()[:dispatch],
      d: %{
        "target" => target,
        "nonce" => nil,
        "payload" => "test!",
        "queue" => queue_name(),
      },
      ts: :os.system_time(:millisecond),
      t: "QUEUE",
    }

    assert_queued queue_name(), %Payload.QueuedMessage{
      nonce: nil,
      payload: "test!",
      target: target,
      queue: queue_name(),
    }
  end
end
