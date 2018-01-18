defmodule Loggix do

  @moduledoc """
  Loggix
  ----
  A custom implementation for Elixir Logger module.
  - Using GenEvent for handle log events.

  ## Configration

  Tell Logger Loggix as backend `config/config.ex`.
  ```
  config :logger,
    backends: [{Loggix, :dev_log}, {Loggix, :json_log}]
  config :logger, :dev_log,
    format: "[$level] $metadata $message [$time]", # configure format
    metadata: [:uuid, :is_auth], # configure metadatas
    rotate: %{max_bytes: 4096, size: 4} # configure log rotation. max_bytes: max byte size of 1 file, size : max count of rotate log file.
  config :logger, :json_log,
  json_encoder: Poison # configure json encoder, which has the function `encode!/2`, which returns iodata.
  ```

  ## Format

  Default formatting style is below:

  ```
  @log_default_format "$time $metadata [$level] $message
  "
  ```

  You can configure a custom formatting style `format : "..."` in config/config.exs.

  ## JSON Encoding

  if json_encoder will specified in configration. json_encoder.encode!/1 will executed.
  Ex. json_encoder: Poison
  Poison.encode!(%{level: "", message: "", time : ""})...
  if json_encoder option is not existed in config/config.exs, formatting style will follow 'format' configration.


  ## Log Rotation

  Logrotate configration which like `erlang.log` can be customized.

  - size
    + it will specify a log generation size, default is 5.
  - max_bytes
    + it will specify max byte of one log.

  ### Example

  For Example, if you specify max_bytes is 1024, size is 4.

  - 0
  ```
  `new data` : 2 byte => dev.log : 1024 byte
  ```
  - 1
  ```
  dev_log =(rename)=> dev_log.1

  then touch dev_log : 0 byte
  ```

  - 2

  ```
  `new data : 2 byte` => dev_log : 0 byte
  dev_log.1 : 1024 byte
  ```

  - 3

  ```
  dev_log : 2 byte
  dev_log.1 : 1024 byte
  ```
  """
  @behaviour :gen_event

  #####################
  # type annotations. #
  #####################
  @type path :: String.t
  @type level :: Logger.level
  @type metadata :: [atom]
  @type format :: String.t
  @type file :: :file.io_device
  @type inode :: File.Stat.t
  @type json_encoder :: Module.t

  @log_default_format "$time $metadata [$level] $message\n"

  def init({__MODULE__, name}) do
    {:ok, configure(name, [])}
  end

  def handle_call({:configure, opts}, %{name: name} = state) do
    {:ok, :ok, configure(name, opts, state)}
  end

  def handle_call(:path, %{path: path} = state) do
    {:ok, {:ok, path}, state}
  end

  def handle_event({level, _gl, {Logger, message, timestamps, metadata}}, %{level: min_level, metadata_filter: metadata_filter} = state) do
    if (is_nil(min_level) or
      Logger.compare_levels(level, min_level) != :lt) and
      metadata_matches?(metadata, metadata_filter) do
      log_event(level, message, timestamps, metadata, state)
    else
      {:ok, state}
    end
  end

  def handle_event(:flush, state) do
    {:ok, state}
  end

  def code_change(_old, state, _extra) do
    {:ok, state}
  end

  def terminate(reason, %{io_device: io_device} = state) do
    File.close(io_device)
    IO.puts("Loggix was terminated. reason=#{inspect(reason)}")
    {:ok, state}
  end

  def handle_info(_message, state) do
    {:ok, state}
  end

  ####################
  # helper functions #
  ####################
  defp log_event(_level, _message, _timestamps, _metadata, %{path: nil} = state) do
    {:ok, state}
  end
  defp log_event(level, message, timestamps, metadata, %{path: path, io_device: nil} = state) when is_binary(path) do
    case open_log(path) do
      {:ok, io_device, inode} ->
        log_event(level, message, timestamps, metadata, %{state | io_device: io_device, inode: inode})
      _ ->
        {:ok, state}
    end
  end
  defp log_event(level, message, timestamps, metadata, %{path: path, io_device: io_device, inode: inode, rotate: rotate} = state) when is_binary(path) do
    if !is_nil(inode) and inode == get_inode(path) and rotate(path, rotate) do
      output = format(level, message, timestamps, metadata, state)
      try do
        IO.write(io_device, output)
        {:ok, state}
      rescue
        ErlangError ->
          case open_log(path) do
            {:ok, io_device, inode} ->
              IO.write(io_device, prune(output))
              {:ok, %{state | io_device: io_device, inode: inode}}
            _other ->
              {:ok, %{state | io_device: nil, inode: nil}}
          end
      end
    else
      File.close(io_device)
      log_event(level, message, timestamps, metadata, %{state | io_device: nil, inode: nil})
    end
  end

  defp open_log(path) do
    open_dir =
      path
      |> Path.dirname()
      |> File.mkdir_p()
    case open_dir do
      :ok ->
        case File.open(path, [:append, :utf8]) do
          {:ok, io_device} ->
            {:ok, io_device, get_inode(path)}
          other ->
            other
        end
      other ->
        other
    end
  end

  defp format(level, message, timestamps, metadata, %{format: format, metadata: metadata_keys, json_encoder: json_encoder}) when is_nil(json_encoder) do
    Logger.Formatter.format(format, level, message, timestamps, reduce_metadata(metadata, metadata_keys))
  end
  defp format(level, message, timestamps, metadata, state) do
    format_json(level, message, timestamps, metadata, state)
  end

  defp format_json(level, message, timestamps, metadata, %{metadata: metadata_keys, json_encoder: json_encoder}) do
    metadata_map =
      reduce_metadata(metadata, metadata_keys)
      |> Enum.into(%{})
    json_encoder.encode!(Map.merge(%{
      level: level,
      message: IO.iodata_to_binary(message),
      time: format_time(timestamps),
    }, metadata_map)) <>
      "\n"
  end

  defp format_time({date, time}) do
    fmt_date =
      format_date(date)
      |> IO.iodata_to_binary()
    fmt_time =
      format_time(time)
      |> IO.iodata_to_binary()
    "#{fmt_date} #{fmt_time}"
  end

  defp rename_file(path, keep) do
    File.rm("#{path}.#{keep}")
    :ok = Enum.each(keep - 1..1, &File.rename("#{path}.#{&1}", "#{path}.#{&1 + 1}"))
    case File.rename(path, "#{path}.1") do
      :ok ->
        false
      {:error, _} ->
        true
    end
  end

  # for log rotate.
  defp rotate(path, %{max_bytes: max_bytes, keep: keep}) when is_integer(max_bytes) and is_integer(keep) and keep > 0 do
    case File.stat(path) do
      {:ok, %{size: size}} ->
        if size >= max_bytes do
          rename_file(path, keep)
        else
          true
        end
      _ ->
        true
    end
  end
  defp rotate(_path, nil), do: true

  @spec reduce_metadata([atom], [atom]) :: [{atom, atom}]
  defp reduce_metadata(metadata, keys) when is_list(keys) do
    Enum.reduce(keys, [], fn key, acc ->
      (case Keyword.fetch(metadata, key) do
        {:ok, value} ->
          [{key, value} | acc]
        :error ->
          acc
      end)
    end)
    |> Enum.reverse()
  end
  defp reduce_metadata(_metadata, _keys), do: []

  @spec metadata_matches?(Keyword.t, Keyword.t | nil) :: boolean
  defp metadata_matches?(_metadata, nil), do: true
  defp metadata_matches?(_metadata, []), do: true
  defp metadata_matches?(metadata, [{k, v} | rest]) do
    # check if all keys of metadata_filter exist in metadata
    case Keyword.fetch(metadata, k) do
      {:ok, ^v} ->
        metadata_matches?(metadata, rest)
      _ ->
        false
    end
  end

  @spec get_inode(String.t) :: term | nil
  defp get_inode(path) do
    case File.stat(path) do
      {:ok, %File.Stat{inode: inode}} ->
        inode
      {:error, _} ->
        nil
    end
  end

  @spec configure(atom, map) :: %{}
  defp configure(name, opts) do
    state = %{
      name: nil,
      path: nil,
      io_device: nil,
      inode: nil,
      level: nil,
      format: nil,
      metadata: nil,
      json_encoder: nil,
      rotate: nil,
      metadata_filter: nil,
    }
    configure(name, opts, state)
  end
  defp configure(name, opts, state) do
    env = Application.get_env(:logger, name, [])
    opts = Keyword.merge(env, opts)
    Application.put_env(:logger, name, opts)

    level = Keyword.get(opts, :level, :debug)
    metadata = Keyword.get(opts, :metadata, [])
    metadata_filter = Keyword.get(opts, :metadata_filter, nil)
    format =
      Keyword.get(opts, :format, @log_default_format)
      |> Logger.Formatter.compile()
    path = Keyword.get(opts, :path, nil)
    json_encoder = Keyword.get(opts, :json_encoder, nil)
    rotate = Keyword.get(opts, :rotate, nil)

    %{state |
      name: name,
      path: path,
      format: format,
      level: level,
      metadata: metadata,
      json_encoder: json_encoder,
      rotate: rotate,
      metadata_filter: metadata_filter,
    }
  end

  @replacement "�"
  def prune(binary) when is_binary(binary), do: prune_binary(binary, "")
  def prune([h | t]) when h in 0..1_114_111, do: [h | prune(t)]
  def prune([h | t]), do: [prune(h) | prune(t)]
  def prune([]), do: []
  def prune(_), do: @replacement

  defp prune_binary(<<h::utf8, t::binary>>, acc) do
    prune_binary(t, <<acc::binary, h::utf8>>)
  end
  defp prune_binary(<<_, t::binary>>, acc) do
    prune_binary(t, <<acc::binary, @replacement>>)
  end
  defp prune_binary(<<>>, acc) do
    acc
  end

  defp format_time({hh, mi, ss, ms}) do
    [pad2(hh), ?:, pad2(mi), ?:, pad2(ss), ?., pad3(ms)]
  end

  defp format_date({yy, mm, dd}) do
    [Integer.to_string(yy), ?-, pad2(mm), ?-, pad2(dd)]
  end

  defp pad3(int) when int < 100 and int > 10, do: [?0, Integer.to_string(int)]
  defp pad3(int) when int < 10, do: [?0, ?0, Integer.to_string(int)]
  defp pad3(int), do: Integer.to_string(int)

  defp pad2(int) when int < 10, do: [?0, Integer.to_string(int)]
  defp pad2(int), do: Integer.to_string(int)
end
