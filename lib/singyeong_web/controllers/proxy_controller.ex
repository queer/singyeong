defmodule SingyeongWeb.ProxyController do
  use SingyeongWeb, :controller

  alias Singyeong.Proxy

  def proxy(conn, params) do
    # {
    #   method: "POST",
    #   route: "/webscale/memes",
    #   body: {
    #     "webscale": "memes"
    #   },
    #   headers: {
    #     "authorization": "potato",
    #     "X-Webscale-Meme": "mongodb"
    #   },
    #   query: {
    #     // See example queries in PROTOCOL.md
    #     // Do NOT provide nonce, payload, ...
    #     // Only thing sent here is the `target` part of a routed message
    #   }
    # }
    ip = Proxy.convert_ip conn
    cond do
      is_nil params["method"] ->
        conn
        |> put_status(400)
        |> json(%{"method" => ["no method provided"]})

      is_nil params["route"] ->
        conn
        |> put_status(400)
        |> json(%{"route" => ["no route provided"]})

      is_nil params["query"] ->
        conn
        |> put_status(400)
        |> json(%{"query" => ["no query provided"]})

      true ->
        # Headers and body are optional
        request =
          %Proxy.ProxiedRequest{
            method: params["method"],
            route: params["route"],
            body: params["body"] || "",
            headers: params["headers"] || %{},
            query: params["query"],
          }

        proxy_request conn, ip, request
    end
  end

  defp proxy_request(conn, ip, request) do
    {status, res} = Proxy.proxy ip, request
    case status do
      :ok ->
        res.headers
        |> Enum.reduce(conn, fn({k, v}, c) ->
          put_resp_header c, String.downcase(k), v
        end)
        |> put_status(res.status)
        |> text(res.body)

      :error ->
        conn
        |> put_status(400)
        |> json(%{"errors" => [res]})
    end
  end
end
