defmodule Singyeong.EncodingTest do
  use ExUnit.Case
  alias Singyeong.Gateway
  alias Singyeong.Gateway.Payload

  test "that JSON payload encoding works" do
    {:text, payload} = Payload.create_payload :dispatch, %{"test" => "test"}
    {:text, encoded} = Gateway.encode_real "json", payload
    decoded = Jiffy.decode! encoded
    assert payload.ts == decoded["ts"]
    assert payload.t == decoded["t"]
    assert payload.op == decoded["op"]
    assert payload.d["test"] == decoded["d"]["test"]
  end

  test "that ETF payload encoding works" do
    {:text, payload} = Payload.create_payload :dispatch, %{"test" => "test"}
    {:binary, encoded} = Gateway.encode_real "etf", payload
    decoded = :erlang.binary_to_term encoded
    assert payload.ts == decoded[:ts]
    assert payload.t == decoded[:t]
    assert payload.op == decoded[:op]
    assert payload.d["test"] == decoded[:d]["test"]
  end

  test "that msgpack payload encoding works" do
    {:text, payload} = Payload.create_payload :dispatch, %{"test" => "test"}
    {:binary, encoded} = Gateway.encode_real "msgpack", payload
    decoded = Msgpax.unpack! encoded
    assert payload.ts == decoded["ts"]
    assert payload.t == decoded["t"]
    assert payload.op == decoded["op"]
    assert payload.d["test"] == decoded["d"]["test"]
  end
end
