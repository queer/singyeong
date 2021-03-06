defmodule SingyeongWeb.ProxyControllerTest do
  use SingyeongWeb.ConnCase
  use SingyeongWeb.ChannelCase
  alias Singyeong.Gateway
  alias Singyeong.Gateway.Handler.Identify
  alias Singyeong.Gateway.Payload
  alias Singyeong.PluginManager
  alias Singyeong.Store
  alias Singyeong.Utils
  alias SingyeongWeb.Router.Helpers, as: Routes

  doctest Singyeong.Proxy

  @app_id "test-app-1"
  @client_id "client-1"

  setup do
    PluginManager.init()
    Store.start()

    on_exit "cleanup", fn ->
      Gateway.cleanup @app_id, @client_id
      Store.stop()
    end

    {:ok, socket: socket(SingyeongWeb.Transport.Raw, nil, [])}
  end

  defp identify(socket, @app_id, @client_id) do
    Identify.handle socket, %Payload{
      op: Gateway.opcodes_name()[:identify],
      d: %Payload.IdentifyRequest{
        client_id: @client_id,
        app_id: @app_id,
        auth: nil,
        ip: "https://echo.amy.gg",
      },
      t: nil,
      ts: Utils.now(),
    }
  end

  @tag capture_log: true
  test "that proxying GET requests works", %{socket: socket} do
    if System.get_env("DISABLE_PROXY_TESTS") do
      assert true
    else
      identify socket, @app_id, @client_id
      proxy_request = %{
        "method" => "GET",
        "route" => "/",
        "body" => nil,
        "headers" => %{
          "Content-Type" => "application/json",
        },
        "query" => %{
          "application" => @app_id,
          "ops" => [],
        }
      }

      # Attempt a proxied HTTP request
      # This is done using an echo server I have set up mainly just so that it
      # doesn't have to spin up and shut down an HTTP server as part of testing
      # because figuring that out was more work.
      # TODO: Should just spin up a local HTTP server someday...
      conn = build_conn()
      res =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(Routes.proxy_path(conn, :proxy), Jason.encode!(proxy_request))
        |> json_response(200)

      assert %{} == res
    end
  end

  @tag capture_log: true
  test "that proxying POST requests works", %{socket: socket} do
    if System.get_env("DISABLE_PROXY_TESTS") do
      assert true
    else
      # Serious stuff

      # IDENTIFY with the gateway so that we have everything we need set up
      # This is tested in another location
      @app_id = "test-app-1"
      @client_id = "client-1"

      identify socket, @app_id, @client_id

      proxy_body = %{
        "test" => "key",
        "map" => %{
          "this" => "is a map",
        },
      }
      proxy_request = %{
        "method" => "POST",
        "route" => "/",
        "body" => proxy_body,
        "headers" => %{
          "Content-Type" => "application/json",
        },
        "query" => %{
          "application" => @app_id,
          "ops" => [],
        }
      }

      # Attempt a proxied HTTP request
      # This is done using an echo server I have set up mainly just so that it
      # doesn't have to spin up and shut down an HTTP server as part of testing
      # because figuring that out was more work.
      # TODO: Should just spin up a local HTTP server someday...
      conn = build_conn()
      res =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(Routes.proxy_path(conn, :proxy), Jason.encode!(proxy_request))
        |> json_response(200)

      assert proxy_body == res
    end
  end
end
