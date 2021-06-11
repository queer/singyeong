defmodule Singyeong.Gateway.Handler.Identify do
  @moduledoc false

  use Singyeong.Gateway.Handler
  alias Singyeong.Gateway.Handler.ConnState
  alias Singyeong.Metadata
  alias Singyeong.Metadata.UpdateQueue
  alias Singyeong.PluginManager
  alias Singyeong.Store
  alias Singyeong.Store.Client

  @impl Singyeong.Gateway.Handler
  def handle(%Socket{} = socket, %Payload{
    d: %Payload.IdentifyRequest{
      app_id: app_id,
      client_id: client_id,
      ip: ip,
      auth: auth,
      namespace: ns,
      initial_metadata: initial_metadata,
      receive_client_updates: receive_client_updates,
    },
  }) do
    if is_binary(client_id) and is_binary(app_id) do
      # If the client doesn't specify its own ip (eg. for routing to a specific
      # port for HTTP), we fall back to the socket-assign ip, which is derived
      # from peer data in the transport.

      case PluginManager.plugin_auth(auth, ip) do
        status when status in [:ok, :restricted] ->
          restricted = status == :restricted
          receive_client_updates = if restricted, do: false, else: receive_client_updates
          encoding = socket.assigns[:encoding]
          unless Store.client_exists?(app_id, client_id) do
            # Client doesn't exist, add to store and okay it
            finish_identify app_id, client_id, socket, ip,
                restricted, encoding, ns, receive_client_updates,
                process_initial_metadata(initial_metadata)
          else
            # If we already have a client, reject outright
            "#{client_id}: already registered for app #{app_id}"
            |> Payload.close_with_error
            |> Gateway.craft_response
          end

        {:error, errors} ->
          "auth: failed: internal error"
          |> Payload.close_with_error(errors)
          |> Gateway.craft_response
      end
    else
      Gateway.handle_missing_data()
    end
  end

  defp process_initial_metadata(data) when not is_nil(data) do
    case Store.validate_metadata(data) do
      {:ok, _} = out -> out
      {:error, _} = err -> err
    end
  end

  defp process_initial_metadata(_), do: {:ok, {%{}, %{}}}

  defp finish_identify(_, _, _, _, _, _, _, _, {:error, errors}) do
    "initial metadata: invalid"
    |> Payload.close_with_error(errors)
    |> Gateway.craft_response
  end

  defp finish_identify(
    app_id,
    client_id,
    socket,
    ip,
    restricted?,
    encoding,
    ns,
    receive_client_updates,
    {:ok, {initial_types, initial_metadata}}
  ) do
    queue_worker = UpdateQueue.name app_id, client_id
    DynamicSupervisor.start_child Singyeong.MetadataQueueSupervisor,
      {UpdateQueue, %{name: queue_worker}}

    client_ip = if restricted?, do: nil, else: ip
    base_metadata = Metadata.base restricted?, encoding, client_ip, ns, receive_client_updates
    # We merge base into initial because base needs to win
    metadata = Map.merge initial_metadata, base_metadata
    types = Map.merge initial_types, Metadata.base_types()

    client =
      %Client{
        app_id: app_id,
        client_id: client_id,
        metadata: metadata,
        metadata_types: types,
        socket_pid: socket.transport_pid,
        socket_ip: client_ip,
        queues: [],
      }

    {:ok, _} = Store.add_client client

    if restricted? do
      Logger.info "[GATEWAY] Got new RESTRICTED socket #{app_id}:#{client_id} @ #{ip}"
    else
      Logger.info "[GATEWAY] Got new socket #{app_id}:#{client_id} @ #{ip}"
    end
    ConnState.send_update app_id, :connect
    :ready
    |> Payload.create_payload(%{"client_id" => client_id, "restricted" => restricted?})
    |> Gateway.craft_response(%{app_id: app_id, client_id: client_id, restricted: restricted?, encoding: encoding})
  end
end
