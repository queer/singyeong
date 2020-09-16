defmodule Singyeong.UtilsTest do
  use ExUnit.Case
  alias Singyeong.Utils

  test "that list concat works" do
    assert [1, 2] == Utils.fast_list_concat([1], [2])
    refute [2, 1] == Utils.fast_list_concat([1], [2])
    assert [1, 2] == Utils.fast_list_concat(1, [2])
    assert [1, 2] == Utils.fast_list_concat([1], 2)
  end

  test "that checking for modules existing works" do
    assert Utils.module_loaded?(String)
    refute Utils.module_loaded?(:this_module_does_not_exist)
  end

  test "that IP-to-string works as expected" do
    assert "127.0.0.1" == Utils.ip_to_string({127, 0, 0, 1})
    assert "2001:0db8:0000:0000:0000:8a2e:0370:7334" == Utils.ip_to_string({
        0x2001,
        0x0db8,
        0x0000,
        0x0000,
        0x0000,
        0x8a2e,
        0x0370,
        0x7334,
      })
  end

  test "that route parsing works" do
    assert {:ok, %{}} == Utils.parse_route("/test", "/test")
    assert {:ok, %{}} == Utils.parse_route("/test/test-2", "/test/test-2")
    assert {:ok, %{"param" => "2"}} == Utils.parse_route("/test/:param", "/test/2")
    assert {:ok, %{"param" => "2", "test_param" => "4"}} == Utils.parse_route("/test/:param/:test_param", "/test/2/4")
    assert {:ok, %{"user" => "test_user"}} == Utils.parse_route("/test/:user", "/test/test_user")
    assert {:ok, %{"user" => "test-user"}} == Utils.parse_route("/test/:user", "/test/test-user")

    assert :error == Utils.parse_route("/test", "/test/test/test")
    assert :error == Utils.parse_route("/test/:param", "/test/test/test")
    assert :error == Utils.parse_route("/test/test/test", "/test/")
  end
end
