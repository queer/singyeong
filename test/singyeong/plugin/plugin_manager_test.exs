defmodule Singyeong.PluginManagerTest do
  use ExUnit.Case
  alias Singyeong.Utils

  test "that plugin loading works" do
    Singyeong.PluginManager.load_plugin_from_zip "priv/test/plugin/singyeong_plugin_test.zip"
    assert Utils.module_loaded? SingyeongPluginTest
  end
end
