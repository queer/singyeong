defmodule SingyeongWeb.Router do
  use SingyeongWeb, :router
  alias Singyeong.Config
  alias Singyeong.PluginManager
  alias Singyeong.Utils

  pipeline :api do
    plug :add_ip
    plug :accepts, ["json"]

    plug Plug.Parsers,
      parsers: [:urlencoded, :multipart, :json],
      pass: ["*/*"],
      json_decoder: Jason
  end

  pipeline :authenticated_routes do
    plug :authenticate
  end

  scope "/api", SingyeongWeb do
    pipe_through :api

    scope "/v1" do
      pipe_through :authenticated_routes
      forward "/plugin", Plugs.PluginRouter
      post "/proxy", ProxyController, :proxy
    end

    get "/version", GenericController, :versions
  end

  scope "/", SingyeongWeb do
    get     "/",      GenericController, :gateway_redirect
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

  def add_ip(conn, _) do
    ip = Utils.ip_to_string conn.remote_ip
    assign conn, :ip, ip
  end

  def authenticate(conn, _) do
    auth =
      case get_req_header(conn, "authorization") do
        l when is_list(l) and length(l) > 0 ->
          hd(l)
        _ ->
          nil
      end

    cond do
      PluginManager.plugins_for_auth() == [] and Config.auth() == nil ->
        conn

      PluginManager.plugins_for_auth() == [] and Config.auth() != nil ->
        if auth == Config.auth() do
          conn
        else
          conn
          |> put_status(401)
          |> json(%{"status" => "error", "error" => "not authorized"})
          |> halt()
        end

      PluginManager.plugins_for_auth() != [] ->
        case PluginManager.plugin_auth(auth, conn.assigns.ip) do
          :ok ->
            conn

          _ ->
            conn
            |> put_status(401)
            |> json(%{"status" => "error", "error" => "not authorized"})
            |> halt()
        end
    end
  end
end
