defmodule Singyeong.ProxyTest do
  use ExUnit.Case
  doctest Singyeong.Proxy
  alias Singyeong.Proxy

  test "can proxy a request" do
    if System.get_env("DISABLE_PROXY_TESTS") do
      assert true
    else
      # Serious stuff
      # TODO: Actually implement this...
    end
  end
end
