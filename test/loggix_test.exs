defmodule LoggixTest do
  use ExUnit.Case, async: false
  require Logger

  @default_path "test/logs/test.log"
  @backend {Loggix, :test}

  Logger.add_backend(@backend)

  setup do
    :ok = config([path: @default_path, level: :debug])
    on_exit fn ->
      path() && File.rm_rf!(Path.dirname(path()))
    end
    :ok
  end

  test "creates log file" do
    Logger.debug("this is a test message")
    assert log() =~ "this is a test message"
  end

  test "can configure format" do
    config([path: @default_path, format: "$message [$level]\n"])

    Logger.debug("hello")
    assert log() =~ "hello [debug]"
  end

  defp path() do
    {:ok, path} = :gen_event.call(Logger, @backend, :path)
    path
  end

  defp log() do
    log = File.read!(path())
    log
  end

  defp config(opts) do
    :ok = Logger.configure_backend(@backend, opts)
    :ok
  end
end
