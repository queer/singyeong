defmodule Singyeong.Plugin.DispatchTest do
  use SingyeongWeb.ChannelCase, async: false
  alias Singyeong.{Gateway, MnesiaStore, PluginManager, Utils}
  alias Singyeong.Gateway.Dispatch
  alias Singyeong.Gateway.GatewayResponse
  alias Singyeong.Gateway.Payload
  alias SingyeongWeb.Transport

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

  @tag :plugin
  @tag capture_log: true
  test "that a :ok dispatch works", %{socket: socket} do
    assert Utils.module_loaded? SingyeongPluginTest
    refute [] == PluginManager.plugins()
    refute [] == PluginManager.plugins_for_event(:custom_events, "TEST")
    # IDENTIFY with the gateway so that we have everything we need set up
    # This is tested in another location
    Gateway.handle_identify socket, %{
      op: Gateway.opcodes_name()[:identify],
      d: %{
        "client_id" => @client_id,
        "application_id" => @app_id,
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

  @tag :plugin
  @tag capture_log: true
  test "that a :halt dispatch works", %{socket: socket} do
    assert Utils.module_loaded? SingyeongPluginTest
    refute [] == PluginManager.plugins()
    refute [] == PluginManager.plugins_for_event(:custom_events, "HALT")
    # IDENTIFY with the gateway so that we have everything we need set up
    # This is tested in another location
    Gateway.handle_identify socket, %{
      op: Gateway.opcodes_name()[:identify],
      d: %{
        "client_id" => @client_id,
        "application_id" => @app_id,
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

  @tag :plugin
  @tag capture_log: true
  test "that an :error dispatch works", %{socket: socket} do
    assert Utils.module_loaded? SingyeongPluginTest
    refute [] == PluginManager.plugins()
    refute [] == PluginManager.plugins_for_event(:custom_events, "ERROR")
    # IDENTIFY with the gateway so that we have everything we need set up
    # This is tested in another location
    Gateway.handle_identify socket, %{
      op: Gateway.opcodes_name()[:identify],
      d: %{
        "client_id" => @client_id,
        "application_id" => @app_id,
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

  @tag :plugin
  @tag capture_log: true
  test "that an :error with undo dispatch works", %{socket: socket} do
    assert Utils.module_loaded? SingyeongPluginTest
    refute [] == PluginManager.plugins()
    refute [] == PluginManager.plugins_for_event(:custom_events, "ERROR_WITH_UNDO")
    # IDENTIFY with the gateway so that we have everything we need set up
    # This is tested in another location
    Gateway.handle_identify socket, %{
      op: Gateway.opcodes_name()[:identify],
      d: %{
        "client_id" => @client_id,
        "application_id" => @app_id,
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
        t: "ERROR_WITH_UNDO",
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
    assert "Error processing plugin event ERROR_WITH_UNDO" == msg
    assert "Manually requested error" == reason
    assert [] == undo_errors
    assert ts <= :os.system_time(:millisecond)
  end

  @tag :plugin
  @tag capture_log: true
  test "that an :error with undo error dispatch works", %{socket: socket} do
    assert Utils.module_loaded? SingyeongPluginTest
    refute [] == PluginManager.plugins()
    refute [] == PluginManager.plugins_for_event(:custom_events, "ERROR_WITH_UNDO")
    # IDENTIFY with the gateway so that we have everything we need set up
    # This is tested in another location
    Gateway.handle_identify socket, %{
      op: Gateway.opcodes_name()[:identify],
      d: %{
        "client_id" => @client_id,
        "application_id" => @app_id,
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
        t: "ERROR_WITH_UNDO_ERROR",
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
    assert "Error processing plugin event ERROR_WITH_UNDO_ERROR" == msg
    assert "Manually requested error" == reason
    assert ["undo error"] == undo_errors
    assert ts <= :os.system_time(:millisecond)
  end

  @tag :plugin
  @tag capture_log: true
  test "that dispatch via `Gateway.handle_dispatch` works as expected", %{socket: socket} do
    # IDENTIFY with the gateway so that we have everything we need set up
    # This is tested in another location
    Gateway.handle_identify socket, %{
      op: Gateway.opcodes_name()[:identify],
      d: %{
        "client_id" => @client_id,
        "application_id" => @app_id,
        "auth" => nil,
        "tags" => ["test", "webscale"]
      },
      ts: :os.system_time(:millisecond),
      t: nil,
    }

    target = %{
      "application" => @app_id,
      "optional" => true,
      "ops" => nil
    }
    payload = %{}
    nonce = "1"
    # Actually do and test the dispatch
    dispatch =
      %Payload{
        t: "SEND",
        d: %{
          "target" => target,
          "payload" => payload,
          "nonce" => nonce,
        }
      }

    %GatewayResponse{assigns: %{}, response: frames} = Gateway.handle_dispatch socket, dispatch
    now = :os.system_time :millisecond
    op = Gateway.opcodes_name()[:dispatch]
    assert [] == frames
    expected =
      %Payload{
        d: %{
          "payload" => payload,
          "nonce" => nonce
        },
        op: op,
        ts: now,
        t: "SEND",
      }

    Process.sleep 100
    # assert_receive / assert_received exist, but we have the issue that
    # waiting for a message to be received may actually take longer than 1ms -
    # especially if we "send" the initial message near the end of a millisecond
    # - meaning that we could have timestamp variance between the expected
    # ts and the ts that the gateway sends back. We can get around this by
    # pulling the message from the process' mailbox ourselves, and do the
    # "pattern matching" manually with == instead of doing a real pattern
    # match.
    {:messages, msgs} = :erlang.process_info self(), :messages
    outgoing_payload = hd msgs
    {:push, {:text, encoded_payload}, _} = Transport.Raw.handle_info outgoing_payload,
        {%{channels: %{}, channels_inverse: %{}}, socket}
    decoded_payload = Jason.decode! encoded_payload
    assert expected.d == decoded_payload["d"]
    assert expected.op == decoded_payload["op"]
    assert expected.t == decoded_payload["t"]
    # Really this should be within ~1ms or so, but there's a host of possible
    # things that could make it not work out.
    assert 10 > abs(expected.ts - decoded_payload["ts"])
  end
end
