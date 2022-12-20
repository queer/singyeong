defmodule Singyeong.MessageDispatcher do
  @moduledoc """
  The message dispatcher is responsible for sending messages to a set of
  client pids inside of an application id.
  """

  alias Singyeong.Gateway.Payload
  alias Singyeong.Gateway.Payload.Dispatch
  alias Singyeong.Metadata.Query
  alias Singyeong.Store.Client
  require Logger

  @spec send_message(
        [{node(), [Client.t()]}], # List of clients
        non_neg_integer(), # Number of clients
        Payload.Dispatch.t(), # Payload to send
        boolean(), # Broadcast payload?
        String.t() | nil # Custom event type
      )
      :: {:ok, :dropped}
         | {:ok, :sent}
         | {:error, :no_route}
  def send_message(clients, client_count, dispatch, broadcast?, event_type \\ nil)

  def send_message(_, 0, %Payload.Dispatch{target: %Query{droppable: true}}, _, nil) do
    # No matches and droppable, silently drop
    {:ok, :dropped}
  end

  def send_message([_ | _] = clients, client_count, %Payload.Dispatch{
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

  def send_message(_, 0, _, _, _) do
    {:error, :no_route}
  end
end
