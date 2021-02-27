defmodule Singyeong.Gateway.Handler.Heartbeat do
  @moduledoc false

  use Singyeong.Gateway.Handler
  alias Singyeong.{Metadata, Utils}

  def handle(%Phoenix.Socket{assigns: %{app_id: app_id, client_id: client_id}}, _payload) do
    {:ok, client} = Store.get_client app_id, client_id
    if client != nil do
      {:ok, _} =
        Store.update_client %{
          client | metadata: Map.put(
              client.metadata,
              Metadata.last_heartbeat_time(),
              Utils.now()
            )
        }

      :heartbeat_ack
      |> Payload.create_payload(%{"client_id" => client_id})
      |> Gateway.craft_response
    else
      Gateway.handle_missing_data()
    end
  end
end
