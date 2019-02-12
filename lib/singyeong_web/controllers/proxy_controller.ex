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
        {status, res} = Proxy.proxy ip, request
        case status do
          :ok ->
            ""
          :error ->
            conn
            |> put_status(400)
            |> json(%{"errors" => [res]})
        end
        conn |> json(%{})
    end
  end
end
