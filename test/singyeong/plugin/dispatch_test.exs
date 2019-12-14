defmodule Singyeong.Plugin.DispatchTest do
  use SingyeongWeb.ChannelCase, async: false
  alias Singyeong.{Gateway, MnesiaStore, PluginManager, Utils}
  alias Singyeong.Gateway.Dispatch
  alias Singyeong.Gateway.Payload

  @client_id "client-1"
  @app_id "test-app-1"

  @dispatch_op Gateway.opcodes_name()[:dispatch]

  setup do
    MnesiaStore.initialize()
    PluginManager.init ["priv/test/plugin/singyeong_plugin_test.zip"]
    socket = socket SingyeongWeb.Transport.Raw, nil, [client_id: @client_id, app_id: @app_id]

    on_exit "cleanup", fn ->
      Gateway.cleanup socket, @app_id, @client_id
      MnesiaStore.shutdown()
    end

    {:ok, socket: socket}
  end

  @tag capture_log: true
  test "that a TEST dispatch works", %{socket: socket} do
    assert Utils.module_loaded? SingyeongPluginTest
    refute [] == PluginManager.plugins()
    refute [] == PluginManager.plugins_for_event("TEST")
    # IDENTIFY with the gateway so that we have everything we need set up
    # This is tested in another location
    Gateway.handle_identify socket, %{
      op: Gateway.opcodes_name()[:identify],
      d: %{
        "client_id" => @client_id,
        "application_id" => @app_id,
        "reconnect" => false,
        "auth" => nil,
        "tags" => ["test", "webscale"]
      },
      ts: :os.system_time(:millisecond),
      t: nil,
    }

    # Actually do and test the dispatch
    dispatch =
      %Payload{
        op: @dispatch_op,
        t: "TEST",
        d: "test data"
      }

    {:ok, frames} = Dispatch.handle_dispatch socket, dispatch
    [frame] = frames
    {ws_op, frame} = frame
    assert :text = ws_op
    %Singyeong.Gateway.Payload{
      d: d,
      op: op,
      t: t,
      ts: ts,
    } = frame
    assert @dispatch_op == op
    assert "TEST" == t
    assert "some cool test data" == d
    assert ts <= :os.system_time(:millisecond)
  end

  @tag capture_log: true
  test "that a HALT dispatch works", %{socket: socket} do
    assert Utils.module_loaded? SingyeongPluginTest
    refute [] == PluginManager.plugins()
    refute [] == PluginManager.plugins_for_event("HALT")
    # IDENTIFY with the gateway so that we have everything we need set up
    # This is tested in another location
    Gateway.handle_identify socket, %{
      op: Gateway.opcodes_name()[:identify],
      d: %{
        "client_id" => @client_id,
        "application_id" => @app_id,
        "reconnect" => false,
        "auth" => nil,
        "tags" => ["test", "webscale"]
      },
      ts: :os.system_time(:millisecond),
      t: nil,
    }

    # Actually do and test the dispatch
    dispatch =
      %Payload{
        op: @dispatch_op,
        t: "HALT",
        d: "test data"
      }

    {:ok, frames} = Dispatch.handle_dispatch socket, dispatch
    assert [] = frames
  end

  @tag capture_log: true
  test "that an ERROR dispatch works", %{socket: socket} do
    assert Utils.module_loaded? SingyeongPluginTest
    refute [] == PluginManager.plugins()
    refute [] == PluginManager.plugins_for_event("ERROR")
    # IDENTIFY with the gateway so that we have everything we need set up
    # This is tested in another location
    Gateway.handle_identify socket, %{
      op: Gateway.opcodes_name()[:identify],
      d: %{
        "client_id" => @client_id,
        "application_id" => @app_id,
        "reconnect" => false,
        "auth" => nil,
        "tags" => ["test", "webscale"]
      },
      ts: :os.system_time(:millisecond),
      t: nil,
    }

    # Actually do and test the dispatch
    dispatch =
      %Payload{
        op: @dispatch_op,
        t: "ERROR",
        d: "test data"
      }

    {:error, frames} = Dispatch.handle_dispatch socket, dispatch
    {:close, {:text, %Payload{t: t, op: op, ts: ts, d: d}}} = frames
    assert Gateway.opcodes_name()[:invalid] == op
    assert nil == t
    %{
      message: msg,
      reason: reason,
      undo_errors: undo_errors,
    } = d
    assert "Error processing plugin event ERROR" == msg
    assert "Manually requested error" == reason
    assert [] == undo_errors
    assert ts <= :os.system_time(:millisecond)
  end
end