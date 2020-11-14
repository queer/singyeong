use Mix.Config

config :singyeong, SingyeongWeb.Endpoint,
  http: [port: 4001],
  server: false

config :singyeong,
  queue: [
    ack_timeout: 100,
    dlq_time: 100,
    gc_interval: 100,
  ]

config :logger, level: :warn
