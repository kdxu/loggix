defmodule LoggixTest do
  require Logger
  use ExUnit.Case, async: false

  @backend {Loggix, :test}
  Logger.add_backend @backend

  setup do
    {:ok, _started} = Application.ensure_all_started(:logger)
    config [path: "test/logs/test.log", level: :debug, json_encoder: Poison]
    on_exit fn ->
      path() && File.rm_rf!(Path.dirname(path()))
    end
    :ok
  end

  test "does not crash if path isn't set" do
    config path: nil
    Logger.debug "foo"
    assert {:error, :already_present} = Logger.add_backend(@backend)
  end

  test "can configure metadata_filter" do
    config metadata_filter: [md_key: true]
    Logger.debug("shouldn't", md_key: false)
    Logger.debug("should", md_key: true)
    refute log() =~ "shouldn't"
    assert log() =~ "should"
    config metadata_filter: nil
  end

  test "creates log file" do
    Logger.debug("this is a msg")
    assert log() =~ "this is a msg"
  end

  defp path() do
    {:ok, path} = :gen_event.call(Logger, @backend, :path)
    path
  end

  defp log() do
    File.read!(path())
  end

  defp config(opts) do
    Logger.configure_backend(@backend, opts)
  end
end
