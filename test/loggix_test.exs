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

  test "can log utf8 chars" do
    Logger.debug("ß\uFFaa\u0222")
    assert log() =~ "ßﾪȢ"
  end

  test "can configure metadata" do
    config([format: "$metadata[$level] $message\n"])
    config([metadata: [:user_id, :is_login]])

    Logger.debug("hello")
    assert log() =~ "hello"

    Logger.metadata(user_id: "xxx-xxx-xxx-xxx")
    Logger.metadata(is_login: true)
    Logger.debug("hello")
    assert log() =~ "user_id=xxx-xxx-xxx-xxx is_login=true [debug] hello"
    config([metadata: nil])
  end
  test "can configure format" do
    config([format: "$message [$level]\n"])

    Logger.debug("hello")
    assert log() =~ "hello [debug]"
  end

  test "log file rotate" do
    config([format: "$message\n"])
    config([rotate: %{max_bytes: 4, keep: 4}])

    Logger.debug("rotate1")
    Logger.debug("rotate2")
    Logger.debug("rotate3")


    p = path()

    assert File.read!("#{p}.2")  == "rotate1\n"
    assert File.read!("#{p}.1")  == "rotate2\n"
    assert File.read!(p)         == "rotate3\n"

    config([rotate: nil])
  end

  test "json-encoded log" do
    config([json_encoder: Poison])
    Logger.debug("hello")
    msg = Poison.decode!(log())
    assert msg["message"] == "hello"
    config([json_encoder: nil])
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
