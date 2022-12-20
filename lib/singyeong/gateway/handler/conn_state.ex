defmodule Singyeong.Gateway.Handler.ConnState do
  alias Singyeong.Gateway.{Dispatch, Payload}
  alias Singyeong.Metadata.Query

  def send_update(app, mode) do
    Dispatch.send_to_clients %Payload.Dispatch{
        target: %Query{
          ops: [
            {:boolean, :op_eq, "/receive_client_updates", {:value, true}},
          ],
        },
        nonce: nil,
        payload: %{app: app},
      }, true, event(mode)
  end

  defp event(:connect), do: "CLIENT_CONNECTED"
  defp event(:disconnect), do: "CLIENT_DISCONNECTED"
end
