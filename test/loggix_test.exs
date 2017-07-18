defmodule LoggixTest do
  require Logger
  use ExUnit.Case, async: false

  @backend {Loggix, :test}

  Logger.add_backend @backend

  setup do
    config [path: "test/logs/test.log", level: :debug]
    on_exit fn ->
      path() && File.rm_rf!(Path.dirname(path()))
    end
  end

  test "does not crash if path isn't set" do
    config path: nil

    Logger.debug "foo"
    assert {:error, :already_present} = Logger.add_backend(@backend)
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
