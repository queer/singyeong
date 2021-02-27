defmodule SingyeongWeb.Transport.Raw do
  @moduledoc """
  Raw websocket transport. This is used to "override" the default Phoenix
  transport, as I don't want to require that everyone learn the (seemingly
  undocumented?) Phoenix socket/channel protocol.
  """

  @behaviour Phoenix.Socket
  @behaviour Phoenix.Socket.Transport

  alias Singyeong.Gateway
  alias Singyeong.Gateway.Encoding
  alias Singyeong.Gateway.GatewayResponse
  alias Singyeong.Gateway.Payload
  alias Singyeong.Utils
  import Phoenix.Socket, only: [assign: 3]
  require Logger

  # SOCKET BEHAVIOURS #

  def id(_), do: nil

  def connect(_params, socket) do
    {:ok, socket}
  end

  # TRANSPORT BEHAVIOURS #

  def child_spec(opts) do
    Phoenix.Socket.__child_spec__ __MODULE__, opts, []
  end

  def connect(map) do
    # map has a key :connect_info map that contains this, which we want:
    # peer_data: %{address: {127, 0, 0, 1}, port: 49818, ssl_cert: nil},
    {:ok, {channels, socket}} = Phoenix.Socket.__connect__ __MODULE__, map, []

    # Convert the ip
    peer_data = map[:connect_info][:peer_data]
    ip = Utils.ip_to_string peer_data[:address]

    # Check querystring for ex. requested encoding
    %URI{query: query} = map[:connect_info][:uri]
    query =
      query
      |> URI.decode_query(%{"encoding" => "json"})

    if Encoding.validate_encoding(query["encoding"]) do
      socket =
        socket
        |> assign(:ip, ip)
        |> assign(:encoding, query["encoding"])
      {:ok, {channels, socket}}
    else
      # If the encoding is invalid, just throw away the connection
      Logger.warn "[TRANSPORT] Rejecting client from #{ip} with invalid encoding #{query["encoding"]}"
      :error
    end
  end

  def init(state) do
    # Now we are effectively inside the process that maintains the socket.
    res = Phoenix.Socket.__init__ state
    # Once we've initialized and returned, we can actually send the hello payload
    send self(), Payload.create_payload(:hello, Gateway.hello())
    res
  end

  def handle_in({payload, opts}, {channels, socket} = _state) do
    opcode = Keyword.fetch! opts, :opcode
    %GatewayResponse{response: response, assigns: assigns} = Gateway.handle_incoming_payload socket, {opcode, payload}
    # Add assigns
    socket =
      assigns
      |> Map.keys
      |> Enum.reduce(socket, fn(x, acc) ->
        assign acc, x, assigns[x]
      end)

    case response do
      {:text, payload} ->
        {:push, Encoding.encode(socket, payload), {channels, socket}}

      {:close, {:text, payload}} ->
        # My god, why can we not specify custom close codes?
        Gateway.handle_close socket
        Process.send_after self(), {:stop, {:shutdown, :closed}}, 100
        {:push, Encoding.encode(socket, payload), {channels, socket}}

      [] ->
        {:ok, {channels, socket}}

      frames when is_list(frames) ->
        for frame <- frames do
          send self(), frame
        end
        {:ok, {channels, socket}}
    end
  end

  def handle_info({:text, payload} = _msg, {%{channels: _channels, channels_inverse: _channels_inverse}, socket} = state) do
    outgoing = Gateway.Pipeline.process_outgoing_event payload
    encoded_payload = Encoding.encode socket, outgoing
    {:push, encoded_payload, state}
  end

  def handle_info({:stop, reason} = _msg, state) do
    {:stop, reason, state}
  end

  def handle_info(_, state) do
    {:ok, state}
  end

  def terminate(reason, {_channels, socket} = _state) do
    Gateway.handle_close socket
    # TODO: Close codes??
    code = 1000
    Logger.info "[TRANSPORT] Socket for #{socket.assigns[:app_id]}:#{socket.assigns[:client_id]}"
      <> " @ #{socket.assigns[:ip]}"
      <> " closed with code #{inspect code}: #{inspect reason}"
    :ok
  end
end
