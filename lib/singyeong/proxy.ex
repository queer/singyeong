defmodule Singyeong.Proxy do
  @moduledoc """
  Singyeong is capable of proxying HTTP requests between services, while still
  retaining the ability to route requests by metadata.

  Proxied requests are handled by `POST`ing a JSON structure describing how the
  request is to be sent to the `/proxy` endpoint (see API.md). A valid request
  is structured like this:

  ```Javascript
  {
    // The request method. Bodies will only be accepted for methods that
    // actually take a request body.
    "method": "POST",
    // The request body. Will only be accepted for methods that take a request
    // body.
    "body": {
      // ...
    },
    // Any headers that need to be sent. Singyeong will set the X-Forwarded-For
    // header for you.
    "headers": {
      "header": "value",
      // ...
    },
    // The routing query used to send the request to a target service.
    "query": {
      // ...
    }
  }
  ```
  """
  alias Singyeong.Cluster
  alias Singyeong.MnesiaStore
  require Logger

  @methods [
    "GET",
    "HEAD",
    "POST",
    "PUT",
    "DELETE",
    "CONNECT",
    "OPTIONS",
    "TRACE",
    "PATCH",
  ]
  @unsupported_methods [
    "CONNECT",
    "OPTIONS",
    "TRACE",
  ]
  @body_methods [
    "POST",
    "PATCH",
    "PUT",
    "DELETE",
    "MOVE",
  ]

  defmodule ProxiedRequest do
    @moduledoc """
    An incoming request that needs to be proxied.
    """
    @type t :: %ProxiedRequest{method: binary(), route: binary(), body: any(), headers: map(), query: map()}
    defstruct [:method, :route, :body, :headers, :query]
  end
  defmodule ProxiedResponse do
    @moduledoc """
    A response from a request that has been successfully proxied.
    """
    @type t :: %ProxiedResponse{status: integer(), body: any(), headers: list()}
    defstruct [:status, :body, :headers]
  end

  @spec requires_body?(binary()) :: boolean
  defp requires_body?(method) do
    method in @body_methods
  end

  @spec valid_method?(binary()) :: boolean
  defp valid_method?(method) do
    method in @methods
  end

  @spec supported_method?(binary()) :: boolean
  defp supported_method?(method) do
    method not in @unsupported_methods
  end

  @spec proxy(binary(), ProxiedRequest.t) :: {:ok, ProxiedResponse.t} | {:error, binary()}
  def proxy(client_ip, request) do
    # TODO: Circuit-breaker or similar here

    # Build header keylist
    headers =
      request.headers
      |> Map.keys
      |> Enum.reduce([], fn(header, acc) ->
        value = request.headers[header]
        [{header, value} | acc]
      end)
    headers = [{"X-Forwarded-For", client_ip} | headers]
    # Verify body + method
    cond do
      not valid_method?(request.method) ->
        # Can't proxy stuff that doesn't exist in the HTTP standard
        {:error, "#{request.method} is not a valid method! (valid methods: #{inspect @methods})"}
      not supported_method?(request.method) ->
        # Some stuff is just useless to support (imo)...
        {:error, "#{request.method} is not a supported method! (not supported: #{inspect @unsupported_methods})"}
      requires_body?(request.method) and is_nil(request.body) ->
        # If it requires a body and we don't have one, give up and cry.
        {:error, "requires body but none given (you probably wanted to send empty-string)"}
      not requires_body?(request.method) and not (is_nil(request.body) or request.body == "") ->
        # If it doesn't require a body and we have one, give up and cry.
        {:error, "no body required but one given (you probably wanted to send nil)"}
      true ->
        # Otherwise just do whatever
        targets = Cluster.query request.query
        valid_targets =
          targets
          |> Enum.filter(fn({_, {_, res}}) ->
            res != []
          end)
          |> Enum.into(%{})
        matched_client_ids =
          valid_targets
          |> Map.values
          |> Enum.map(fn({_, res}) -> res end)
          |> Enum.concat
        if Enum.empty?(matched_client_ids) do
          {:error, "no matches"}
        else
          # Pick a random node
          {node, {target_application, clients}} = Enum.random valid_targets
          client_id = Enum.random clients
          Task.await run_proxied_request(node, target_application, client_id, request, headers)
        end
    end
  end

  defp run_proxied_request(node, app_id, client, request, headers) do
    fake_local_node = Cluster.fake_local_node()
    # Build up the send function so we can potentially run it on remote nodes
    send_fn = fn ->
      method_atom =
        request.method
        |> String.downcase
        |> String.to_atom
      {ip_status, target_ip} = MnesiaStore.get_socket_ip app_id, client
      send_proxied_request request, method_atom, headers, ip_status, target_ip
    end
    # Actually run the send function
    case node do
      ^fake_local_node ->
        Task.Supervisor.async Singyeong.TaskSupervisor, send_fn
      _ ->
        Task.Supervisor.async {Singyeong.TaskSupervisor, node}, send_fn
    end
  end

  defp send_proxied_request(request, method_atom, headers, ip_status, target_ip) do
    case ip_status do
      :ok ->
        encoded_body = encode_body request.body
        dest_with_protocol =
          case target_ip do
            "http://" <> _ip_or_domain ->
              target_ip
            "https://" <> _ip_or_domain ->
              target_ip
            _ ->
              "http://#{target_ip}"
          end
        {status, response} = HTTPoison.request(
          method_atom,
          "#{dest_with_protocol}/#{request.route}",
          encoded_body,
          headers,
          [timeout: 5_000]
        )
        case status do
          :ok ->
            {:ok, %ProxiedResponse{
              status: response.status_code,
              body: response.body,
              headers: response.headers,
            }}
          :error ->
            {:error, Exception.message(response)}
        end
      :error ->
        {:error, "no target ip"}
    end
  end

  defp encode_body(body) do
    cond do
      is_map(body) ->
        Jiffy.encode! body
      is_list(body) ->
        Jiffy.encode! body
      is_binary(body) ->
        body
      true ->
        Jiffy.encode! body
    end
  end

  @spec convert_ip(Plug.Conn.t) :: binary()
  def convert_ip(conn) do
    conn.remote_ip
    |> :inet_parse.ntoa
    |> to_string
  end
end
