defmodule Singyeong.DispatchCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      # Copied from channel_case.ex
      import Phoenix.ChannelTest
      import Singyeong.QueueCase
      import Phoenix.Socket, only: [assign: 3]
      alias Singyeong.{
        Gateway,
        Gateway.GatewayResponse,
        Gateway.Payload,
        PluginManager,
        Store,
        Utils,
      }
      alias SingyeongWeb.Transport.Raw

      @client_id "client-1"
      @app_id "test-app-1"

      @endpoint SingyeongWeb.Endpoint
      @moduletag capture_log: true

      setup do
        Store.start()
        PluginManager.init()

        socket = socket Raw, nil, [client_id: @client_id, app_id: @app_id]

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
            ts: Utils.now(),
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
    end
  end
end
