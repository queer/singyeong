defmodule SingyeongWeb.DiscoveryControllerTest do
  use SingyeongWeb.ConnCase
  alias SingyeongWeb.Router.Helpers, as: Routes
  alias Singyeong.MnesiaStore

  setup do
    on_exit fn ->
      System.delete_env "AUTH"
    end
  end

  test "that discovering services via querystring tags works", %{conn: conn} do
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

    # ugly boring gross cleanup stuff qwq
    MnesiaStore.shutdown()
  end

  test "that discovering services with authentication works", %{conn: conn} do
    # ugly boring gross setup stuff qwq
    MnesiaStore.initialize()
    one_tag = ["webscale"]
    two_tags = ["test", "test-tag"]
    MnesiaStore.add_client "test-app-1", "client-1"
    MnesiaStore.add_client "test-app-2", "client-1"
    MnesiaStore.set_tags "test-app-1", "client-1", one_tag
    MnesiaStore.set_tags "test-app-2", "client-1", two_tags

    # Interesting test stuff begins here
    System.put_env "AUTH", "1234"

    res1 =
      build_conn()
      |> put_req_header("authorization", "12345678")
      |> get(Routes.discovery_path(conn, :by_tags, q: "[%22webscale%22]"))
      |> json_response(401)
    assert "error" == res1["status"]

    res2 =
      build_conn()
      |> put_req_header("authorization", "1234")
      |> get(Routes.discovery_path(conn, :by_tags, q: "[%22webscale%22]"))
      |> json_response(200)
    assert "ok" == res2["status"]

    apps = res2["result"]
    assert ["test-app-1"] == apps

    # ugly boring gross cleanup stuff qwq
    MnesiaStore.shutdown()
    # Env is automatically cleaned up (see setup above)
  end
end
