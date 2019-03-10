defmodule Singyeong.GatewayTest do
  use SingyeongWeb.ChannelCase
  alias Singyeong.Gateway
  alias Singyeong.Gateway.GatewayResponse

  setup do
    Singyeong.MnesiaStore.initialize()

    on_exit "cleanup", fn ->
      Singyeong.MnesiaStore.shutdown()
    end

    {:ok, socket: socket()}
  end

  test "identify works correctly", %{socket: socket} do
    client_id = "client-1"
    app_id = "test-app-1"

    # IO.inspect socket, pretty: true

    %GatewayResponse{
      response: response,
      assigns: assigns
    } =
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

    assert %{client_id: client_id, app_id: app_id, restricted: false} == assigns

    # Destructure it
    {:text, response} = response
    # Decode it
    response = Jason.decode! response
    # Actually test it
    assert is_map response["d"]
    d = response["d"]
    assert client_id == d["client_id"]
    refute d["restricted"]
  end
end
