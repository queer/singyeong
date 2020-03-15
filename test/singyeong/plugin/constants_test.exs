defmodule Singyeong.Plugin.ConstantsTest do
  use ExUnit.Case
  alias Singyeong.Gateway
  alias Singyeong.Plugin.Constants

  test "that constants are all correct" do
    assert Gateway.opcodes_id() == Constants.gateway_opcodes()
    assert Gateway.opcodes_name() == Constants.gateway_opcodes_by_name()
  end
end
