# Loggix

[![hex.pm version](https://img.shields.io/hexpm/v/loggix.svg)](https://hex.pm/packages/loggix)
[![hex.pm](https://img.shields.io/hexpm/l/loggix.svg)](https://github.com/kdxu/loggix/blob/master/LICENSE)


A Log Implimentation Tool with Logger.

## Concept

- Use `GenEvent`

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `loggix` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:loggix, "~> 0.0.5"}]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/loggix](https://hexdocs.pm/loggix).

## Configration

For telling logger to configiration of `loggix`.

```elixir
config :logger,
  backends: [{Loggix, :error_log}]
config :logger, :error_log,
  path: "var/log/error_log"
  level: :error
  json_encoder: Poison
  metadata: [:user_id, :is_auth]
```


* path : String - the path for a log file
* level : Logger.Level - the logging level for backend
* format : String - the log format
* metadata : String - the metadata to include

## TODO

- ~~JSON, XML Encode feature~~
- metadata filter
