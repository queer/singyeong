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

  defmodule ProxiedRequest do
    defstruct [:method, :body, :headers, :query]
  end
  defmodule ProxiedResponse do
    defstruct [:status, :body, :headers]
  end

  @spec proxy(binary(), ProxiedRequest.t) :: ProxiedResponse.t
  def proxy(client_ip, request) do
    # TODO: Implement
  end

  #def memes(conn) do
  #  to_string(:inet_parse.ntoa(conn.remote_ip))
  #end
end
