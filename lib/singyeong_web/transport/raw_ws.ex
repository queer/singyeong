defmodule SingyeongWeb.Transport.RawWs do
  # Ported from https://github.com/satom99/phx_raws/blob/master/lib/transports.ex
  # Thank mr adam

  import Plug.Conn, only: [
    fetch_query_params: 1,
    send_resp: 3
  ]
  alias Phoenix.Socket.Transport

  def default_config do
    [
      timeout: 60_000,
      transport_log: false,
      cowboy: SingyeongWeb.Transport.CowboyWebsocket # Phoenix.Endpoint.CowboyWebSocket
    ]
  end

  def init(%Plug.Conn{method: "GET"} = conn, {endpoint, handler, transport}) do
    {_, opts} = handler.__transport__(transport)

    conn =
      conn
      |> fetch_query_params
      |> Transport.transport_log(opts[:transport_log])
      |> Transport.force_ssl(handler, endpoint, opts)
      |> Transport.check_origin(handler, endpoint, opts)

    case conn do
      %{halted: false} = conn ->
        case Transport.connect(endpoint, handler, transport, __MODULE__, nil, conn.params) do
          {:ok, socket} ->
            # ip = Singyeong.Proxy.convert_ip conn
            # socket = Phoenix.Socket.assign socket, "ip", ip
            {:ok, conn, {__MODULE__, {socket, opts}}}
          :error ->
            send_resp conn, :forbidden, ""
            {:error, conn}
        end
      _ ->
        {:error, conn}
    end
  end

  def init(conn, _) do
    send_resp conn, :bad_request, ""
    {:error, conn}
  end

  def ws_init({socket, config}) do
    Process.flag :trap_exit, true
    {:ok, %{socket: socket}, config[:timeout]}
  end

  def ws_handle(op, data, state) do
    state.socket.handler
    |> apply(:handle, [op, data, state])
    |> case do
      frames when is_list(frames) ->
        {:reply, frames, state}
      {frames, state} when is_list(frames) ->
        {:reply, frames, state}
      {{op, data}, state} ->
        {:reply, {op, data}, state}
      {op, data} ->
        {:reply, {op, data}, state}
      {op, data, state} ->
        {:reply, {op, data}, state}
      %{} = state ->
        {:ok, state}
      _ ->
        {:ok, state}
    end
  end

  def ws_info({:socket_push, frames}, state) when is_list(frames) do
    {:reply, frames, state}
  end

  def ws_info({_op, _data} = tuple, state) do
    {:reply, tuple, state}
  end

  def ws_info(_tuple, state), do: {:ok, state}

  def ws_close(code, state) do
    ws_handle :closed, {code, :normal}, state
  end

  def ws_terminate(reason, state) do
    # 1005 "Indicates that no status code was provided even though one was expected."
    ws_handle :closed, {1005, reason}, state
  end
end
