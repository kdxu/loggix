defmodule LoggixTest do
  use ExUnit.Case, async: false
  require Logger

  @backend {Loggix, :test}

  Logger.add_backend(@backend, [flush: true])

  setup do
    config([path: "test/logs/test.log", level: :debug])
    on_exit fn ->
      path() && File.rm_rf!(Path.dirname(path()))
    end
  end

  test "does not crash if path isn't set" do
    config([path: nil])
    Logger.debug("foo")
    assert {:error, :already_present} = Logger.add_backend(@backend)
  end

  test "can configure metadata_filter" do
    config([metadata_filter: [test_key: true]])
    Logger.debug("cat😾", test_key: false)
    Logger.debug("dog🐶", test_key: true)
    refute log() =~ "cat😾"
    assert log() =~ "dog🐶"
    config([metadata_filter: nil])
  end

  test "creates log file" do
    refute File.exists?(path())
    Logger.debug("this is a test message")
    assert File.exists?(path())
    assert log() =~ "this is a test message"
  end

  test "can log utf8 chars" do
    Logger.debug("ß\uFFaa\u0222🐶")
    assert log() =~ "ßﾪȢ"
  end

  test "can configure format" do
    config([format: "$message [$level]\n"])

    Logger.debug("hello")
    assert log() =~ "hello [debug]"
  end

  test "can configure metadata" do
    config([metadata: [:user_id, :is_login], format: "$metadata[$level] $message\n"])

    Logger.debug("hello")
    assert log() =~ "hello"

    Logger.debug("hello", user_id: "xxx-xxx-xxx-xxx", is_login: true)
    assert log() =~ "user_id=xxx-xxx-xxx-xxx is_login=true [debug] hello"
    config([metadata: nil])
  end

  test "can configure level" do
    config([level: :info])

    Logger.debug("hello")
    refute File.exists?(path())
  end

  test "can configure path" do
    new_path = "test/logs/test.log.2"
    config([path: new_path])
    assert new_path == path()
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

  test "log file does not rotate" do
    config([format: "$message\n"])
    config([rotate: %{max_bytes: 50, keep: 4}])

    words = ["rotate1", "rotate2", "rotate3", "rotate4", "rotate5"]
    words |> Enum.map(&(Logger.debug(&1)))

    assert log() == Enum.join(words, "\n") <> "\n"

    config([rotate: nil])
  end

  test "json-encoded log" do
    config([json_encoder: Poison, metadata: [:user_id]])
    Logger.debug("hello", user_id: "xxx=xxxx")
    msg = Poison.decode!(log())
    assert msg["message"] == "hello"
    assert msg["user_id"] == "xxx=xxxx"
    config([json_encoder: nil])
    config([metadata: []])
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
