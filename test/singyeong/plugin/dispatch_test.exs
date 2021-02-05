defmodule Singyeong.Plugin.DispatchTest do
  # use SingyeongWeb.ChannelCase, async: false
  use Singyeong.DispatchCase
  import Phoenix.Socket, only: [assign: 3]
  alias Singyeong.{Gateway, PluginManager, Utils}
  alias Singyeong.Gateway.Dispatch
  alias Singyeong.Gateway.GatewayResponse
  alias Singyeong.Gateway.Handler.DispatchEvent
  alias Singyeong.Gateway.Payload
  alias Singyeong.Gateway.Payload.Error
  alias Singyeong.Metadata.Query
  alias Singyeong.PluginManager
  alias Singyeong.Store
  alias Singyeong.Utils
  alias SingyeongWeb.Transport

  @dispatch_op Gateway.opcodes_name()[:dispatch]

  @moduletag :plugin

  setup_all do
    PluginManager.init ["priv/test/plugin/singyeong_plugin_test.zip"]
  end

  @tag capture_log: true
  test "that a :ok dispatch works", %{socket: socket} do
    assert Utils.module_loaded? SingyeongPluginTest
    refute [] == PluginManager.plugins()
    refute [] == PluginManager.plugins_for_event(:custom_events, "TEST")

    # Actually do and test the dispatch
    dispatch =
      %Payload{
        op: @dispatch_op,
        t: "TEST",
        d: "test data",
        ts: Utils.now(),
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
    assert ts <= Utils.now()
  end

  @tag capture_log: true
  test "that a :halt dispatch works", %{socket: socket} do
    assert Utils.module_loaded? SingyeongPluginTest
    refute [] == PluginManager.plugins()
    refute [] == PluginManager.plugins_for_event(:custom_events, "HALT")

    # Actually do and test the dispatch
    dispatch =
      %Payload{
        op: @dispatch_op,
        t: "HALT",
        d: "test data",
        ts: Utils.now(),
      }

    {:ok, frames} = Dispatch.handle_dispatch socket, dispatch
    assert [] = frames
  end

  @tag capture_log: true
  test "that an :error dispatch works", %{socket: socket} do
    assert Utils.module_loaded? SingyeongPluginTest
    refute [] == PluginManager.plugins()
    refute [] == PluginManager.plugins_for_event(:custom_events, "ERROR")

    # Actually do and test the dispatch
    dispatch =
      %Payload{
        op: @dispatch_op,
        t: "ERROR",
        d: "test data",
        ts: Utils.now(),
      }

    {:error, frames} = Dispatch.handle_dispatch socket, dispatch
    {:text, %Payload{t: t, op: op, ts: ts, d: d}} = frames
    assert Gateway.opcodes_name()[:invalid] == op
    assert nil == t
    %Error{
      error: msg,
      extra_info: %{
        reason: reason,
        undo_errors: undo_errors,
      },
    } = d
    assert "Error processing plugin event ERROR" == msg
    assert "Manually requested error" == reason
    assert [] == undo_errors
    assert ts <= Utils.now()
  end

  @tag capture_log: true
  test "that an :error with undo dispatch works", %{socket: socket} do
    assert Utils.module_loaded? SingyeongPluginTest
    refute [] == PluginManager.plugins()
    refute [] == PluginManager.plugins_for_event(:custom_events, "ERROR_WITH_UNDO")

    # Actually do and test the dispatch
    dispatch =
      %Payload{
        op: @dispatch_op,
        t: "ERROR_WITH_UNDO",
        d: "test data",
        ts: Utils.now(),
      }

    {:error, frames} = Dispatch.handle_dispatch socket, dispatch
    {:text, %Payload{t: t, op: op, ts: ts, d: d}} = frames
    assert Gateway.opcodes_name()[:invalid] == op
    assert nil == t
    %Error{
      error: msg,
      extra_info: %{
        reason: reason,
        undo_errors: undo_errors,
      },
    } = d
    assert "Error processing plugin event ERROR_WITH_UNDO" == msg
    assert "Manually requested error" == reason
    assert [] == undo_errors
    assert ts <= Utils.now()
  end

  @tag capture_log: true
  test "that an :error with undo error dispatch works", %{socket: socket} do
    assert Utils.module_loaded? SingyeongPluginTest
    refute [] == PluginManager.plugins()
    refute [] == PluginManager.plugins_for_event(:custom_events, "ERROR_WITH_UNDO")

    # Actually do and test the dispatch
    dispatch =
      %Payload{
        op: @dispatch_op,
        t: "ERROR_WITH_UNDO_ERROR",
        d: "test data",
        ts: Utils.now(),
      }

    {:error, frames} = Dispatch.handle_dispatch socket, dispatch
    {:text, %Payload{t: t, op: op, ts: ts, d: d}} = frames
    assert Gateway.opcodes_name()[:invalid] == op
    assert nil == t
    %Error{
      error: msg,
      extra_info: %{
        reason: reason,
        undo_errors: undo_errors,
      },
    } = d
    assert "Error processing plugin event ERROR_WITH_UNDO_ERROR" == msg
    assert "Manually requested error" == reason
    assert ["undo error"] == undo_errors
    assert ts <= Utils.now()
  end

  @tag capture_log: true
  test "that dispatch via `Gateway.handle_dispatch` works as expected", %{socket: socket} do
    target = Query.json_to_query %{
      "application" => @app_id,
      "optional" => true,
      "ops" => nil
    }
    payload = %{}
    nonce = "1"
    # Actually do and test the dispatch
    dispatch =
      %Payload{
        op: 4,
        t: "SEND",
        d: %Payload.Dispatch{
          target: target,
          payload: payload,
          nonce: nonce,
        },
        ts: Utils.now(),
      }

    %GatewayResponse{assigns: %{}, response: frames} = DispatchEvent.handle socket, dispatch
    now = Utils.now()
    op = Gateway.opcodes_name()[:dispatch]
    assert [] == frames
    expected =
      %Payload{
        # Unlike other tests, this is EXPECTED to be a stringified map. This is
        # due to the fact that this is running over the raw transport.
        d: %{
          "payload" => payload,
          "nonce" => nonce,
          "target" => nil,
        },
        op: op,
        ts: now,
        t: "SEND",
      }

    outgoing_payload = await_receive_message()
    {:push, {:text, encoded_payload}, _} = Transport.Raw.handle_info outgoing_payload,
        {%{channels: %{}, channels_inverse: %{}}, socket}
    decoded_payload = Jason.decode! encoded_payload
    assert expected.d == decoded_payload["d"]
    assert expected.op == decoded_payload["op"]
    assert expected.t == decoded_payload["t"]
    assert 10 > abs(expected.ts - decoded_payload["ts"])
  end

  defp await_receive_message do
    # assert_receive / assert_received exist, but we have the issue that
    # waiting for a message to be received may actually take longer than 1ms -
    # especially if we "send" the initial message near the end of a millisecond
    # - meaning that we could have timestamp variance between the expected
    # ts and the ts that the gateway sends back. We can get around this by
    # pulling the message from the process' mailbox ourselves, and do the
    # "pattern matching" manually with == instead of doing a real pattern
    # match.
    receive do
      msg -> msg
    after
      5000 -> raise "couldn't recv message in time!"
    end
  end
end
