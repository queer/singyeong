defmodule SingyeongWeb.Transport.Raw do
  @behaviour Phoenix.Socket
  @behaviour Phoenix.Socket.Transport

  alias Singyeong.Gateway
  alias Singyeong.Gateway.GatewayResponse
  alias Singyeong.Gateway.Payload
  import Phoenix.Socket, only: [assign: 3]
  require Logger

  #####################
  # Socket behaviours #
  #####################

  def id(_), do: nil

  def connect(_params, socket) do
    {:ok, socket}
  end

  ########################
  # Transport behaviours #
  ########################

  def child_spec(opts) do
    Phoenix.Socket.__child_spec__(__MODULE__, opts)
  end

  def connect(map) do
    # map has a key :connect_info map that contains this, which we want:
    # peer_data: %{address: {127, 0, 0, 1}, port: 49818, ssl_cert: nil},
    {:ok, {channels, socket}} = Phoenix.Socket.__connect__(__MODULE__, map, false)
    # Convert the ip
    peer_data = map[:connect_info][:peer_data]
    ip =
      case peer_data[:address] do
        {a, b, c, d} ->
          "#{a}.#{b}.#{c}.#{d}"
        {a, b, c, d, e, f, g, h} ->
          "#{hex a}:#{hex b}:#{hex c}:#{hex d}:#{hex e}:#{hex f}:#{hex g}:#{hex h}"
      end
    socket =
      socket
      |> assign(:ip, ip)
    {:ok, {channels, socket}}
  end

  def init(state) do
    # Now we are effectively inside the process that maintains the socket.
    res = Phoenix.Socket.__init__(state)
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
        if socket.assigns[:etf] do
          # Send the frame as an ETF binary payload
          {:push, {:binary, :erlang.term_to_binary(payload)}, {channels, socket}}
        else
          # Just a single text frame to send
          {:push, {:text, Jason.encode!(payload)}, {channels, socket}}
        end
      {:close, {:text, payload}} ->
        {:push, {:text, payload}, {channels, socket}}
      [] ->
        {:ok, {channels, socket}}
      frames when is_list(frames) ->
        # A list of frames to send
        Logger.error "[TRANSPORT] Was asked to send a frame list, but I don't know how to do that!"
        {:ok, {channels, socket}}
      _ ->
        # Anything else probably doesn't need a response
        {:ok, {channels, socket}}
    end
  end

  def handle_info({:text, payload} = _msg, {%{channels: _channels, channels_inverse: _channels_inverse}, socket} = state) do
    new_payload =
      if socket.assigns[:etf] do
        # Send the frame as an ETF binary payload
        {:binary, :erlang.term_to_binary(payload)}
      else
        # Just a single text frame to send
        {:text, Jason.encode!(payload)}
      end

    {:push, new_payload, state}
  end

  def handle_info(_, state) do
    {:ok, state}
  end

  def terminate(reason, {_channels, socket} = _state) do
    # TODO: Close codes??
    code = 1000
    Logger.info "[TRANSPORT] Socket for #{socket.assigns[:app_id]}:#{socket.assigns[:client_id]}"
      <> " @ #{socket.assigns[:ip]}"
      <> " closed with code #{inspect code}: #{inspect reason}"
    Gateway.handle_close socket
    :ok
  end

  defp hex(v) do
    Integer.to_string(v, 16)
  end
end
