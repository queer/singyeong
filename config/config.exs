# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config
require Logger

# Configures the endpoint
config :singyeong, SingyeongWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "b+/gXZdeMqYfvqhrGomnUZXcWS25i2zKBgndyLTky3JUj7AAXoHuB6HRuk4D41Du",
  render_errors: [view: SingyeongWeb.ErrorView, accepts: ~w(json)],
  pubsub: [name: Singyeong.PubSub,
           adapter: Phoenix.PubSub.PG2]

# Configures Elixir's Logger
config :logger, :console,
  format: "[$time] $metadata[$level]$levelpad $message\n",
  metadata: [:user_id]

config :phoenix, :format_encoders,
  json: Jason
config :phoenix, :json_library, Jason

config :singyeong,
  store: Singyeong.Store.Mnesia,
  auth: System.get_env("AUTH"),
  port: System.get_env("PORT"),
  clustering: System.get_env("CLUSTERING"),
  cookie: System.get_env("COOKIE"),
  redis_dsn: System.get_env("REDIS_DSN")

config :singyeong_plugin,
  gateway_module: Singyeong.Gateway,
  payload_module: Singyeong.Gateway.Payload

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env}.exs"

# Import custom configs. This should override EVERYTHING else, and so it must
# stay at the very bottom.
# We need to guard it to avoid exceptions being thrown, because the other
# choice is relying on silly wildcard expansion hacks.
if File.exists?("config/custom.exs") do
  import_config "custom.exs"
end
