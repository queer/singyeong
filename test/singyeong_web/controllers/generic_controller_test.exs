defmodule SingyeongWeb.GenericControllerTest do
  use SingyeongWeb.ConnCase
  use SingyeongWeb.ChannelCase
  alias Singyeong.Gateway
  alias Singyeong.PluginManager
  alias Singyeong.Store
  alias Singyeong.Utils
  alias SingyeongWeb.Router.Helpers, as: Routes

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
    Gateway.handle_identify socket, %{
      op: Gateway.opcodes_name()[:identify],
      d: %{
        "client_id" => @client_id,
        "application_id" => @app_id,
        "auth" => nil,
      },
      t: nil,
      ts: Utils.now(),
    }
  end

  @tag capture_log: true
  test "that running queries works", %{socket: socket} do
    identify socket, @app_id, @client_id
    request =
      %{
        "application" => @app_id,
        "ops" => [],
      }

    conn = build_conn()
    res =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(Routes.generic_path(conn, :query), Jason.encode!(request))
      |> json_response(200)

    assert [%{
      "app_id" => "test-app-1",
      "client_id" => "client-1",
      "metadata" => %{
        "encoding" => nil,
        "ip" => nil,
        "restricted" => false
      },
      "metadata_types" => %{
        "encoding" => "string",
        "ip" => "string",
        "restricted" => "boolean",
      },
      "queues" => [],
      "socket_ip" => nil,
    }] = res
  end
end
