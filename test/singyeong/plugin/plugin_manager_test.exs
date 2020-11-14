defmodule Singyeong.PluginManagerTest do
  use ExUnit.Case
  alias Singyeong.{PluginManager, Utils}

  @moduletag :plugin

  @tag capture_log: true
  test "that plugin loading works" do
    PluginManager.init ["priv/test/plugin/singyeong_plugin_test.zip"]
    assert Utils.module_loaded? SingyeongPluginTest
    PluginManager.shutdown()
  end
end
