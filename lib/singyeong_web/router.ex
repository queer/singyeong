defmodule SingyeongWeb.Router do
  use SingyeongWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug :authenticate
  end

  scope "/api", SingyeongWeb do
    pipe_through :api

    scope "/v1" do
      scope "/discovery" do
        get "/tags", DiscoveryController, :by_tags
      end
    end
  end

  def authenticate(conn, _) do
    auth =
      case get_req_header(conn, "authorization") do
        l when is_list(l) and length(l) > 0 ->
          hd(l)
        _ ->
          nil
      end
    configured_auth = System.get_env "AUTH"
    if configured_auth != nil and auth != configured_auth do
      conn
      |> put_status(401)
      |> json(%{"status" => "error", "error" => "not authorized"})
      |> halt()
    else
      conn
    end
  end
end
