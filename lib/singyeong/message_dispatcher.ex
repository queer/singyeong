defmodule Singyeong.MessageDispatcher do
  @moduledoc """
  The message dispatcher is responsible for sending messages to a set of
  client pids inside of an application id.
  """

  alias Singyeong.Gateway.Payload
  alias Singyeong.Gateway.Payload.Dispatch
  alias Singyeong.Metadata.Query
  alias Singyeong.Store
  alias Singyeong.Store.Client
  require Logger

  @spec send_with_retry(
        Plug.Socket.t() | nil,
        [{Store.app_id(), Client.t()}],
        non_neg_integer(),
        Payload.Dispatch.t(),
        boolean(),
        String.t() | nil
      )
      :: {:ok, :dropped}
         | {:ok, :sent}
         | {:error, :no_route}

  def send_with_retry(socket, clients, client_count, dispatch, broadcast?, event_type \\ nil)

  def send_with_retry(_, _, 0, %Payload.Dispatch{target: %Query{droppable: true}}, _, nil) do
    # No matches and droppable, silently drop
    {:ok, :dropped}
  end

  def send_with_retry(socket, _, 0, %Payload.Dispatch{target: %Query{droppable: false} = target, nonce: nonce}, _, nil) do
    # No matches and not droppable, reply to initiator if possible
    if socket != nil and is_pid(socket.transport_pid) and Process.alive?(socket.transport_pid) do
      failure =
        Payload.create_payload :invalid, %{
          "error" => "no nodes match query for query #{inspect target, pretty: true}",
          "d" => %{
            "nonce" => nonce
          }
        }

      send socket.transport_pid, failure
    end
    {:error, :no_route}
  end

  def send_with_retry(_socket, [_ | _] = clients, client_count, %Payload.Dispatch{
    nonce: nonce,
    payload: payload,
  }, broadcast?, type) when client_count > 0 do
    live_clients =
      Enum.flat_map clients, fn {_, clients} ->
        Enum.map(clients, &(&1.socket_pid))
      end

    payload_type =
      if broadcast? do
        type || "BROADCAST"
      else
        type || "SEND"
      end

    payload =
      Payload.create_payload(:dispatch, payload_type, %Dispatch{
        nonce: nonce,
        payload: payload,
      })

    if broadcast? do
      Manifold.send live_clients, payload
    else
      Manifold.send Enum.random(live_clients), payload
    end
    {:ok, :sent}
  end

  def send_with_retry(_, _, 0, _, _, _) do
    {:error, :no_route}
  end
end
