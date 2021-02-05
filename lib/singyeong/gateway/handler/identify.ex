defmodule Singyeong.Gateway.Handler.Identify do
  use Singyeong.Gateway.Handler
  alias Singyeong.Metadata
  alias Singyeong.Metadata.UpdateQueue
  alias Singyeong.PluginManager
  alias Singyeong.Store.Client

  @impl Singyeong.Gateway.Handler
  def handle(%Socket{} = socket, %Payload{
    d: %Payload.IdentifyRequest{
      app_id: app_id,
      client_id: client_id,
      ip: ip,
      auth: auth,
    },
  }) do
    if is_binary(client_id) and is_binary(app_id) do
      # If the client doesn't specify its own ip (eg. for routing to a specific
      # port for HTTP), we fall back to the socket-assign ip, which is derived
      # from peer data in the transport.

      case PluginManager.plugin_auth(auth, ip) do
        status when status in [:ok, :restricted] ->
          restricted = status == :restricted
          encoding = socket.assigns[:encoding]
          unless Store.client_exists?(app_id, client_id) do
            # Client doesn't exist, add to store and okay it
            finish_identify app_id, client_id, socket, ip, restricted, encoding
          else
            # If we already have a client, reject outright
            "#{client_id}: already registered for app #{app_id}"
            |> Payload.close_with_error
            |> Gateway.craft_response
          end

        {:error, errors} ->
          "Errors occurred during auth"
          |> Payload.close_with_error(errors)
          |> Gateway.craft_response
      end
    else
      Gateway.handle_missing_data()
    end
  end

  defp finish_identify(app_id, client_id, socket, ip, restricted?, encoding) do
    queue_worker = UpdateQueue.name app_id, client_id
    DynamicSupervisor.start_child Singyeong.MetadataQueueSupervisor,
      {UpdateQueue, %{name: queue_worker}}

    client_ip = if restricted?, do: nil, else: ip

    client =
      %Client{
        app_id: app_id,
        client_id: client_id,
        metadata: Metadata.base(restricted?, encoding, client_ip),
        metadata_types: Metadata.base_types(),
        socket_pid: socket.transport_pid,
        socket_ip: client_ip,
        queues: []
      }

    {:ok, _} = Store.add_client client

    if restricted? do
      Logger.info "[GATEWAY] Got new RESTRICTED socket #{app_id}:#{client_id} @ #{ip}"
    else
      Logger.info "[GATEWAY] Got new socket #{app_id}:#{client_id} @ #{ip}"
    end
    :ready
    |> Payload.create_payload(%{"client_id" => client_id, "restricted" => restricted?})
    |> Gateway.craft_response(%{app_id: app_id, client_id: client_id, restricted: restricted?, encoding: encoding})
  end
end
