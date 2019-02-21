defmodule SingyeongWeb.Router do
  use SingyeongWeb, :router
  alias Singyeong.Env

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated_routes do
    plug :authenticate
  end

  scope "/api", SingyeongWeb do
    pipe_through :api

    scope "/v1" do
      pipe_through :authenticated_routes
      scope "/discovery" do
        get "/tags", DiscoveryController, :by_tags
      end
      post "/proxy", ProxyController, :proxy
    end

    get "/version", GenericController, :versions
  end

  scope "/", SingyeongWeb do
    # lol
    # catch all missing routes and 404 them nicely instead of Phoenix's
    # generated error page
    get     "/*path", GenericController, :not_found
    post    "/*path", GenericController, :not_found
    put     "/*path", GenericController, :not_found
    patch   "/*path", GenericController, :not_found
    delete  "/*path", GenericController, :not_found
    head    "/*path", GenericController, :not_found
    connect "/*path", GenericController, :not_found
    options "/*path", GenericController, :not_found
    trace   "/*path", GenericController, :not_found
  end

  def authenticate(conn, _) do
    auth =
      case get_req_header(conn, "authorization") do
        l when is_list(l) and length(l) > 0 ->
          hd(l)
        _ ->
          nil
      end
    if Env.auth() != nil and auth != Env.auth() do
      conn
      |> put_status(401)
      |> json(%{"status" => "error", "error" => "not authorized"})
      |> halt()
    else
      conn
    end
  end
end
