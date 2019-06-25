defmodule Singyeong.GatewayTest do
  use SingyeongWeb.ChannelCase
  alias Singyeong.Gateway
  alias Singyeong.Gateway.GatewayResponse

  setup do
    Singyeong.MnesiaStore.initialize()

    on_exit "cleanup", fn ->
      Singyeong.MnesiaStore.shutdown()
    end

    {:ok, []}
  end

  test "that identify works" do
    client_id = "client-1"
    app_id = "test-app-1"

    socket = socket SingyeongWeb.Transport.Raw, nil, %{encoding: "json"}

    incoming_payload =
      %{
        "op" => Gateway.opcodes_name()[:identify],
        "d" => %{
          "client_id" => client_id,
          "application_id" => app_id,
          "reconnect" => false,
          "auth" => nil,
          "tags" => ["test", "webscale"],
        },
        "t" => :os.system_time(:millisecond),
      }

    %GatewayResponse{
      response: response,
      assigns: assigns
    } =
      Gateway.handle_incoming_payload socket, {:text, Jason.encode!(incoming_payload)}

    assert %{client_id: client_id, app_id: app_id, restricted: false, encoding: "json"} == assigns

    # Destructure it
    {:text, response} = response
    # Payloads are only encoded at the moment of sending, so decoding here
    # isn't necessary
    # response = Jason.decode! response
    # Actually test it
    assert is_map response.d
    d = response.d
    assert client_id == d["client_id"]
    refute d["restricted"]
  end

  test "that ETF identify works" do
    client_id = "client-1"
    app_id = "test-app-1"

    socket = socket SingyeongWeb.Transport.Raw, nil, %{encoding: "etf"}

    incoming_payload =
      %{
        "op" => Gateway.opcodes_name()[:identify],
        "d" => %{
          "client_id" => client_id,
          "application_id" => app_id,
          "reconnect" => false,
          "auth" => nil,
          "tags" => ["test", "webscale"],
        },
        "t" => :os.system_time(:millisecond),
      }

    # Test actually setting ETF mode
    %GatewayResponse{
      response: response,
      assigns: assigns
    } =
      Gateway.handle_incoming_payload socket, {:binary, :erlang.term_to_binary(incoming_payload)}

    assert %{client_id: client_id, app_id: app_id, restricted: false, encoding: "etf"} == assigns

    # Destructure it
    {:text, response} = response
    # Payloads are only encoded at the moment of sending, so decoding here
    # isn't necessary
    # response = Jason.decode! response
    # Actually test it
    assert is_map response.d
    d = response.d
    assert client_id == d["client_id"]
    refute d["restricted"]
  end

  test "that msgpack identify works" do
    client_id = "client-1"
    app_id = "test-app-1"

    socket = socket SingyeongWeb.Transport.Raw, nil, %{encoding: "msgpack"}
    incoming_payload = %{
      "op" => Gateway.opcodes_name()[:identify],
      "d" => %{
        "client_id" => client_id,
        "application_id" => app_id,
        "reconnect" => false,
        "auth" => nil,
        "tags" => ["test", "webscale"],
      },
      "t" => :os.system_time(:millisecond),
    }

    # Test actually setting msgpack mode
    %GatewayResponse{
      response: _response,
      assigns: assigns
    } =
      Gateway.handle_incoming_payload socket, {:binary, Msgpax.pack!(incoming_payload)}

    assert %{client_id: client_id, app_id: app_id, restricted: false, encoding: "msgpack"} == assigns
  end
end
