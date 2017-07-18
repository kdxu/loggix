use Mix.Config

config :logger,
  backends: [{Loggix, :dev}]

config :logger, :dev,
  level: :debug,
  path: "test/logs/dev.log"
