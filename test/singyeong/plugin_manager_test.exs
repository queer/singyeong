defmodule Singyeong.PluginManagerTest do
  use ExUnit.Case
  alias Singyeong.{PluginManager, Utils}

  test "that plugin loading works" do
    PluginManager.load_plugin_from_zip "priv/test/plugin/singyeong_plugin_test.zip"
    assert Utils.module_loaded? SingyeongPluginTest
  end
end
