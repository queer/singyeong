defmodule Singyeong.MessageDispatcher do
  @moduledoc """
  The message dispatcher is responsible for sending messages to a set of
  client pids inside of an application id.
  """

  alias Singyeong.Gateway.Payload

  def send_dispatch(clients, type, msg) do
    clients
    |> Enum.map(fn client ->
      client.socket_pid
    end)
    |> Enum.filter(&(&1 != nil and Process.alive?(&1)))
    |> Enum.each(fn pid ->
      send pid, Payload.create_payload(:dispatch, type, %{
        "nonce" => msg["nonce"],
        "payload" => msg["payload"],
      })
    end)
  end
end
