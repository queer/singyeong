defmodule SingyeongWeb.Router do
  use SingyeongWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", SingyeongWeb do
    pipe_through :api
  end
end
