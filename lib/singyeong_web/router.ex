defmodule SingyeongWeb.Router do
  use SingyeongWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", SingyeongWeb do
    pipe_through :api

    scope "/v1" do
      scope "/discovery" do
        get "/tags", DiscoveryController, :by_tags
      end
    end
  end
end
