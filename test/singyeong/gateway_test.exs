defmodule Singyeong.GatewayTest do
  use SingyeongWeb.ChannelCase
  alias Singyeong.Gateway
  alias Singyeong.Gateway.GatewayResponse
  alias Singyeong.PluginManager
  alias Singyeong.Store
  alias Singyeong.Utils

  @app_id "test-app-1"
  @client_id "client-1"
  @identify %{
    "op" => 1,
    "d" => %{
      "client_id" => @client_id,
      "application_id" => @app_id,
    },
    "t" => nil,
    "ts" => Utils.now(),
  }

  setup do
    Store.start()
    PluginManager.init()

    on_exit "cleanup", fn ->
      Gateway.cleanup @app_id, @client_id
      Store.stop()
    end

    {:ok, []}
  end

  @tag capture_log: true
  test "that identify works" do
    socket = socket SingyeongWeb.Transport.Raw, nil, %{encoding: "json"}

    %GatewayResponse{
      response: response,
      assigns: assigns
    } = Gateway.handle_incoming_payload socket, {:text, Jason.encode!(@identify)}

    assert %{client_id: @client_id, app_id: @app_id, restricted: false, encoding: "json"} == assigns

    # Destructure it
    {:text, response} = response
    # Payloads are only encoded at the moment of sending, so decoding here
    # isn't necessary
    # response = Jason.decode! response
    # Actually test it
    assert is_map response.d
    d = response.d
    assert @client_id == d["client_id"]
    refute d["restricted"]
  end

  @tag capture_log: true
  test "that ETF identify works" do
    socket = socket SingyeongWeb.Transport.Raw, nil, %{encoding: "etf"}

    identify = :erlang.term_to_binary @identify

    # Test actually setting ETF mode
    %GatewayResponse{
      response: response,
      assigns: assigns
    } = Gateway.handle_incoming_payload socket, {:binary, identify}
    assert %{client_id: @client_id, app_id: @app_id, restricted: false, encoding: "etf"} == assigns

    # Destructure it
    {:text, response} = response
    # Payloads are only encoded at the moment of sending, so decoding here
    # isn't necessary
    # response = Jason.decode! response
    # Actually test it
    assert is_map response.d
    d = response.d
    assert @client_id == d["client_id"]
    refute d["restricted"]
  end

  @tag capture_log: true
  test "that msgpack identify works" do
    socket = socket SingyeongWeb.Transport.Raw, nil, %{encoding: "msgpack"}

    # Test actually setting msgpack mode
    %GatewayResponse{
      response: _response,
      assigns: assigns
    } = Gateway.handle_incoming_payload socket, {:binary, Msgpax.pack!(@identify)}

    assert %{client_id: @client_id, app_id: @app_id, restricted: false, encoding: "msgpack"} == assigns
  end
end
