defmodule Singyeong.Gateway.Handler.DispatchEvent do
  @moduledoc false

  use Singyeong.Gateway.Handler
  alias Singyeong.Gateway.{Dispatch, Pipeline}

  def handle(socket, payload) do
    dispatch_type = payload.t
    if Dispatch.can_dispatch?(socket, dispatch_type) do
      processed_payload = Pipeline.process_event_via_pipeline payload, :server
      case processed_payload do
        {:ok, processed} ->
          socket
          |> Dispatch.handle_dispatch(processed)
          |> handle_dispatch_response

        :halted ->
          Gateway.craft_response []

        {:error, close_payload} ->
          Gateway.craft_response [close_payload]
      end
    else
      :invalid
      |> Payload.create_payload(%{"error" => "invalid dispatch type #{dispatch_type} (are you restricted?)"})
      |> Gateway.craft_response
    end
  end

  defp handle_dispatch_response(dispatch_result) do
    case dispatch_result do
      {:ok, %Payload{} = frame} ->
        [frame]
        |> Pipeline.process_outgoing_event
        |> Gateway.craft_response

      {:ok, {:text, %Payload{}} = frame} ->
        frame
        |> Pipeline.process_outgoing_event
        |> Gateway.craft_response

      {:ok, frames} when is_list(frames) ->
        frames
        |> Pipeline.process_outgoing_event
        |> Gateway.craft_response

      {:error, error} ->
        Gateway.craft_response error
    end
  end

  # TODO: This isn't really the right place for these S:
end
