# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

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
  json: Jiffy
config :phoenix, :json_library, Jiffy

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env}.exs"
