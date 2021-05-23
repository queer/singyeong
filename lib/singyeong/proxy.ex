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
  use TypedStruct
  alias Singyeong.Cluster
  alias Singyeong.Metadata.Query
  require Logger

  @timeout :infinity

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

  typedstruct module: ProxiedRequest do
    field :method, String.t()
    field :route, String.t()
    field :body, term()
    field :headers, map()
    field :query, Query.t()
  end

  typedstruct module: ProxiedResponse do
    field :status, integer()
    field :body, any()
    field :headers, map()
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
        query_and_proxy request, headers
    end
  end

  defp query_and_proxy(request, headers) do
    target =
      # Run the query across the cluster...
      request.query
      |> Cluster.query
      |> Map.to_list
      # ...then filter on non-empty client lists...
      |> Enum.filter(fn {_node, clients} when is_list(clients) -> not Enum.empty?(clients) end)
      # ...and finally, pick only one node-client pair
      |> random_client

    if target == nil do
      {:error, "no matches"}
    else
      {node, client} = target
      node
      |> run_proxied_request(client, request, headers)
      |> Task.await(:infinity)
    end
  end

  defp random_client([_ | _] = targets) do
    {node, clients} = Enum.random targets
    {node, Enum.random(clients)}
  end
  defp random_client([]), do: nil

  defp run_proxied_request(node, client, request, headers) do
    fake_local_node = Cluster.fake_local_node()
    # Build up the send function so we can potentially run it on remote nodes
    send_fn = fn ->
      method_atom =
        request.method
        |> String.downcase
        |> String.to_atom

      send_proxied_request request, method_atom, headers, client.socket_ip
    end

    # Actually run the send function
    case node do
      ^fake_local_node ->
        Task.Supervisor.async Singyeong.TaskSupervisor, send_fn, timeout: :infinity

      _ ->
        Task.Supervisor.async {Singyeong.TaskSupervisor, node}, send_fn, timeout: :infinity
    end
  end

  defp send_proxied_request(request, method_atom, headers, target_ip) do
    encoded_body = encode_body request.body
    dest_with_protocol =
      case target_ip do
        "http://" <> _ = dest ->
          "#{dest}/#{request.route}"

        "https://" <> _ = dest ->
          "#{dest}/#{request.route}"

        _ ->
          # We assume that targets are smart enough to upgrade to SSL if needed
          "http://#{target_ip}/#{request.route}"

      end

    {status, response} =
      HTTPoison.request method_atom, dest_with_protocol,
        encoded_body, headers,
        [timeout: @timeout, recv_timeout: @timeout, follow_redirect: true, max_redirects: 10]

    case status do
      :ok ->
        {:ok, %ProxiedResponse{
          status: response.status_code,
          body: response.body,
          headers: Map.new(response.headers),
        }}

      :error ->
        {:error, Exception.message(response)}
    end
  end

  defp encode_body(body) do
    cond do
      is_map(body) ->
        Jason.encode! body

      is_list(body) ->
        Jason.encode! body

      is_binary(body) ->
        body

      true ->
        Jason.encode! body
    end
  end

  @spec convert_ip(Plug.Conn.t) :: binary()
  def convert_ip(conn) do
    conn.remote_ip
    |> :inet_parse.ntoa
    |> to_string
  end
end
