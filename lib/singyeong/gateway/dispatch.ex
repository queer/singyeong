defmodule Singyeong.Gateway.Dispatch do
  alias Singyeong.Metadata.Store

  ## DISPATCH EVENTS ##

  # Note: Dispatch handlers will return nil for okay, or an error string on "failure"

  def handle_dispatch(socket, %{"t" => "UPDATE_METADATA", "d" => data} = _payload) do
    try do
      if Store.validate_metadata?(data) do
        # Reduce metadata and update
        data
        |> Map.keys
        |> Enum.reduce(%{}, fn(x, acc) ->
          Map.put(acc, x, data[x]["value"])
        end)
        |> Store.update_metadata(socket.assigns[:client_id])
        nil
      else
        "invalid metadata"
      end
    rescue
      # Ideally we won't reach this case, but clients can't be trusted :<
      _ ->
        "invalid metadata"
    end
  end
  def handle_dispatch(socket, %{"t" => "SEND", "d" => data} = _payload) do
    # TODO: Query and route
    nil
  end
  def handle_dispatch(socket, %{"t" => "BROADCAST", "d" => data} = _payload) do
    # This is really just a special case of SEND
    # TODO: Query and route
    nil
  end
  def handle_dispatch(_socket, _payload) do
    "invalid dispatch payload"
  end
end
