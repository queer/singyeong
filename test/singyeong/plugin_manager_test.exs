defmodule Singyeong.PluginManagerTest do
  use ExUnit.Case
  alias Singyeong.Utils

  test "that plugin loading works" do
    assert Utils.module_loaded? SingyeongPluginTest
  end
end
