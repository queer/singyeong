defmodule SingyeongWeb.DiscoveryControllerTest do
  use SingyeongWeb.ConnCase
  alias SingyeongWeb.Router.Helpers, as: Routes
  alias Singyeong.MnesiaStore

  test "Can discover services via querystring tags", %{conn: conn} do
    # ugly boring gross setup stuff qwq
    MnesiaStore.initialize()
    many_tags = ["test", "cool", "memes"]
    one_tag = ["webscale"]
    some_tags = ["test", "webscale"]
    MnesiaStore.add_client "test-app-1", "client-1"
    MnesiaStore.add_client "test-app-2", "client-1"
    MnesiaStore.add_client "test-app-3", "client-1"
    MnesiaStore.set_tags "test-app-1", "client-1", many_tags
    MnesiaStore.set_tags "test-app-2", "client-1", one_tag
    MnesiaStore.set_tags "test-app-3", "client-1", some_tags

    # Interesting test stuff begins here

    # Test with passing two tags
    two_tag_res =
      conn
      |> get(Routes.discovery_path(conn, :by_tags, q: "[%22test%22,%20%22webscale%22]"))
      |> json_response(200)
    assert "ok" == two_tag_res["status"]
    two_tag_app_ids = two_tag_res["result"]
    assert ["test-app-3"] == two_tag_app_ids

    # Test with passing only a single tag
    one_tag_res =
      conn
      |> get(Routes.discovery_path(conn, :by_tags, q: "[%22webscale%22]"))
      |> json_response(200)
    assert "ok" == one_tag_res["status"]
    one_tag_app_ids = one_tag_res["result"]
    assert ["test-app-2", "test-app-3"] == one_tag_app_ids

    MnesiaStore.shutdown()
  end
end
