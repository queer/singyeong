defmodule SingyeongWeb.Transport.RawTest do
  use ExUnit.Case
  alias SingyeongWeb.Transport.Raw

  @connect_json %{
    connect_info: %{
      peer_data: %{address: {127, 0, 0, 1}, port: 65_432, ssl_cert: nil},
      uri: %URI{
        authority: "localhost",
        fragment: nil,
        host: "localhost",
        path: "/gateway/websocket",
        port: 4567,
        query: "encoding=json",
        scheme: "http",
        userinfo: nil
      },
      x_headers: []
    },
    endpoint: SingyeongWeb.Endpoint,
    options: [
      connect_info: [:x_headers, :peer_data, :uri],
      path: "/websocket",
      serializer: [
        {Phoenix.Socket.V1.JSONSerializer, "~> 1.0.0"},
        {Phoenix.Socket.V2.JSONSerializer, "~> 2.0.0"}
      ],
      timeout: 60_000,
      transport_log: false,
      compress: false
    ],
    params: %{"encoding" => "json"},
    transport: :websocket
  }

  @connect_etf %{
    connect_info: %{
      peer_data: %{address: {127, 0, 0, 1}, port: 65_432, ssl_cert: nil},
      uri: %URI{
        authority: "localhost",
        fragment: nil,
        host: "localhost",
        path: "/gateway/websocket",
        port: 4567,
        query: "encoding=etf",
        scheme: "http",
        userinfo: nil
      },
      x_headers: []
    },
    endpoint: SingyeongWeb.Endpoint,
    options: [
      connect_info: [:x_headers, :peer_data, :uri],
      path: "/websocket",
      serializer: [
        {Phoenix.Socket.V1.JSONSerializer, "~> 1.0.0"},
        {Phoenix.Socket.V2.JSONSerializer, "~> 2.0.0"}
      ],
      timeout: 60_000,
      transport_log: false,
      compress: false
    ],
    params: %{"encoding" => "etf"},
    transport: :websocket
  }

  @connect_msgpack %{
    connect_info: %{
      peer_data: %{address: {127, 0, 0, 1}, port: 65_432, ssl_cert: nil},
      uri: %URI{
        authority: "localhost",
        fragment: nil,
        host: "localhost",
        path: "/gateway/websocket",
        port: 4567,
        query: "encoding=msgpack",
        scheme: "http",
        userinfo: nil
      },
      x_headers: []
    },
    endpoint: SingyeongWeb.Endpoint,
    options: [
      connect_info: [:x_headers, :peer_data, :uri],
      path: "/websocket",
      serializer: [
        {Phoenix.Socket.V1.JSONSerializer, "~> 1.0.0"},
        {Phoenix.Socket.V2.JSONSerializer, "~> 2.0.0"}
      ],
      timeout: 60_000,
      transport_log: false,
      compress: false
    ],
    params: %{"encoding" => "msgpack"},
    transport: :websocket
  }

  test "that JSON connect works" do
    {:ok, {%{channels: %{}, channels_inverse: %{}}, socket}} = Raw.connect @connect_json
    %{encoding: encoding, ip: ip} = socket.assigns
    assert "json" == encoding
    assert "127.0.0.1" == ip
  end

  test "that ETF connect works" do
    {:ok, {%{channels: %{}, channels_inverse: %{}}, socket}} = Raw.connect @connect_etf
    %{encoding: encoding, ip: ip} = socket.assigns
    assert "etf" == encoding
    assert "127.0.0.1" == ip
  end

  test "that MessagePack connect works" do
    {:ok, {%{channels: %{}, channels_inverse: %{}}, socket}} = Raw.connect @connect_msgpack
    %{encoding: encoding, ip: ip} = socket.assigns
    assert "msgpack" == encoding
    assert "127.0.0.1" == ip
  end
end
