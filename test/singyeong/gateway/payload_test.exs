defmodule Singyeong.Gateway.PayloadTest do
  use ExUnit.Case
  alias Singyeong.Gateway.Payload
  alias Singyeong.Metadata.Query

  test "that SEND decoding works" do
    json =
      %{
        "op" => 4,
        "t" => "SEND",
        "d" => %{
          "nonce" => nil,
          "target" => %{
            "application" => "test",
            "restricted" => false,
            "optional" => false,
            "droppable" => false,
            "ops" => [
              %{
                "key" => %{
                  "$eq" => "value",
                },
              },
            ],
          },
          "payload" => "test",
        }
      }

    assert %Payload{
      op: 4,
      t: "SEND",
      d: %Payload.Dispatch{
        nonce: nil,
        payload: "test",
        target: %Query{
          application: "test",
          restricted: false,
          optional: false,
          droppable: false,
          ops: [
            {:op_eq, {"key", "value"}},
          ],
        },
      }
    } = Payload.from_map json
  end

  test "that QUEUE decoding works" do
    json =
      %{
        "op" => 4,
        "t" => "QUEUE",
        "d" => %{
          "queue" => "test",
          "nonce" => nil,
          "target" => %{
            "application" => "test",
            "restricted" => false,
            "optional" => false,
            "droppable" => false,
            "ops" => [
              %{
                "key" => %{
                  "$eq" => "value",
                },
              },
            ],
          },
          "payload" => "test",
        }
      }

    assert %Payload{
      op: 4,
      t: "QUEUE",
      d: %Payload.QueueInsert{
        queue: "test",
        nonce: nil,
        payload: "test",
        target: %Query{
          application: "test",
          restricted: false,
          optional: false,
          droppable: false,
          ops: [
            {:op_eq, {"key", "value"}},
          ],
        },
      },
    } = Payload.from_map json
  end

  test "that QUEUE_REQUEST decoding works" do
    json =
      %{
        "op" => 4,
        "t" => "QUEUE_REQUEST",
        "d" => %{
          "queue" => "test",
        },
      }

    assert %Payload{
      op: 4,
      t: "QUEUE_REQUEST",
      d: %Payload.QueueRequest{
        queue: "test",
      },
    } = Payload.from_map json
  end

  test "that QUEUE_ACK decoding works" do
    json =
      %{
        "op" => 4,
        "t" => "QUEUE_ACK",
        "d" => %{
          "queue" => "test",
          "id" => "1234",
        },
      }

    assert %Payload{
      op: 4,
      t: "QUEUE_ACK",
      d: %Payload.QueueAck{
        queue: "test",
        id: "1234",
      },
    } = Payload.from_map json
  end
end
