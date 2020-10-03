defmodule Singyeong.Plugin.RestRouteTest do
  use SingyeongWeb.ConnCase
  use SingyeongWeb.ChannelCase
  alias Singyeong.PluginManager
  alias Singyeong.Store
  alias SingyeongWeb.Router

  setup do
    Store.start()
    PluginManager.init ["priv/test/plugin/singyeong_plugin_test.zip"]

    on_exit "cleanup", fn ->
      Store.stop()
      System.delete_env "AUTH"
    end
  end

  @tag capture_log: true
  test "that plugin route proxying works" do
    conn = call Router, :get, "/api/v1/plugin/test"
    assert 200 == conn.status
    assert "Henlo world" == conn.resp_body
  end

  @tag capture_log: true
  test "that plugin route proxying works with params" do
    conn = call Router, :get, "/api/v1/plugin/test/test-param"
    assert 200 == conn.status
    assert "Henlo param: test-param" == conn.resp_body
  end

  defp call(router, verb, path, params \\ nil, script_name \\ []) do
    verb
    |> build_conn(path, params)
    |> Plug.Conn.fetch_query_params
    |> Map.put(:script_name, script_name)
    |> router.call(router.init([]))
  end
end
