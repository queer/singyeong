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
end
