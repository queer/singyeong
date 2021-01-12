# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config
require Logger

################################################################
## Phoenix-specific configuration. You should not touch this. ##
##       Unless, of course, you know what you're doing.       ##
################################################################

# Configures the endpoint
config :singyeong, SingyeongWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "b+/gXZdeMqYfvqhrGomnUZXcWS25i2zKBgndyLTky3JUj7AAXoHuB6HRuk4D41Du",
  render_errors: [view: SingyeongWeb.ErrorView, accepts: ~w(json)],
  pubsub_server: Singyeong.PubSub

# Configures Elixir's Logger
config :logger, :console,
  format: "[$time] $metadata[$level]$levelpad $message\n",
  metadata: [:file, :line]

config :phoenix, :format_encoders,
  json: Jason

config :phoenix, :json_library, Jason

#############################################################################
## 신경-specific configuration. You should NOT edit this file directly, but ##
## instead be creating a `custom.exs` in this directory to override values ##
## with.                                                                   ##
#############################################################################

config :singyeong,
  # The module to use for metadata storage. The default is the built-in mnesia
  # metadata store.
  store: Singyeong.Mnesia.Store,
  # The password to use for authentication. This should be a long, secure
  # password. See the "Security" section in README.md for why. Plugins may
  # ignore this value and use their own authentication scheme. Defaults to no
  # authentication.
  auth: System.get_env("AUTH"),
  # The port to run on. No default. Ideally this will be 80 in prod, and maybe
  # something like 4567 in dev.
  port: System.get_env("PORT"),
  # Whether or not clustering should be activated. Defaults to false. If this
  # option is set, you will also need to set the `cookie` and `redis_dsn`
  # options below.
  clustering: System.get_env("CLUSTERING"),
  # The cookie to use for Erlang distribution. See the following part of the
  # Erlang docs: # http://erlang.org/doc/reference_manual/distributed.html §13.7 Security.
  # This should be just as secure as your auth, as a weak value + a cluster
  # that's open to the public internet = someone else can potentially connect
  # more Erlang nodes to your cluster and work evil.
  cookie: System.get_env("COOKIE"),
  # The Redis connection string. Redis is used for discovery of other cluster
  # members; someday this will be replaced with a more generic clustering
  # strategy thing.
  redis_dsn: System.get_env("REDIS_DSN"),
  # Raft-specific configuration; this is used for message queuing.
  raft: [
    # The zone, or datacentre, that this node is running in. You can use
    # different zones to achieve geodistribution.
    zone: System.get_env("ZONE") || "zone-1",
  ],
  # Message-queuing-specific configuration.
  queue: [
    # How long a message can be awaiting ACK before it times out and is moved
    # to the DLQ.
    ack_timeout: 15_000,
    # How long a message can sit in the DLQ before being moved back into the
    # main queue.
    dlq_time: 15_000,
    # How big the Raft consensus group for queues can be. If you want to keep
    # horizontally scaling, you should set this to a very large value, as no
    # more consensus group members can join once the group is sized at this
    # value.
    group_size: 3,
    # The interval at which queue garbage collection should run. This value
    # shouldn't be too low, or the Erlang scheduler will be thrashing the CPU.
    gc_interval: 1_000,
  ],
  # Metadata-processing-specific configuration.
  metadata: [
    # The interval at which metadata update queues will process pending
    # updates. This value shouldn't be too low, or the Erlang scheduler will be
    # thrashing the CPU.
    queue_interval: 500,
  ]

# Configuration for the plugin API
config :singyeong_plugin,
  # The module providing gateway functionality, ie message processing.
  gateway_module: Singyeong.Gateway,
  # The module providing payload functionality, ie creation of payload structs
  # from whatever data is available.
  payload_module: Singyeong.Gateway.Payload

import_config "#{Mix.env}.exs"

# Import custom configs. This should override EVERYTHING else, and so it must
# stay at the very bottom.
# We need to guard it to avoid exceptions being thrown, because the other
# choice is relying on silly wildcard expansion hacks.
if File.exists?("config/custom.exs") do
  import_config "custom.exs"
end
