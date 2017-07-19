defmodule Loggix do

  @moduledoc"""
  Loggix
  ----
  A custom implementation for Elixir Logger moduale.
  - Using GenEvent for handle log events.

  ## Format

  Default formatting style is below:

  ```
  @log_default_format "$time $metadata [$level] $message\n"
  ```

  You can configure a custom formatting style `format : "..."` in config/config.exs.

  ## JSON Encoding

  if json_encoder will specified in configration. json_encoder.encode!/1 will executed.
  Ex. json_encoder: Poison
  Poison.encode!(%{level: "", message: "", time : ""})...
  if json_encoder option is not existed in config/config.exs, formatting style will follow 'format' configration.
  """

  @behaviour :gen_event

  #####################
  # type annotations. #
  #####################
  @type path  :: String.t
  @type level :: Logger.level
  @type metadata :: [atom]
  @type format :: String.t
  @type file :: :file.io_device
  @type inode :: File.Stat.t

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

  def handle_event({level, _gl, {Logger, message, timestamps, metadata}}, %{level: min_level} = state) do
    if is_nil(min_level == nil) or Logger.compare_levels(level, min_level) != :lt do
      log_event(level, message, timestamps, metadata, state)
    else
      {:ok, state}
    end
  end

  def handle_event(:flush, state) do
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
      IO.write(io_device, output)
      {:ok, state}
    else
      File.close(io_device)
      log_event(level, message, timestamps, metadata, %{state | io_device: nil, inode: nil})
    end
  end

  defp open_log(path) do
    open_dir = path
               |> Path.dirname()
               |> File.mkdir_p()
    case open_dir do
      :ok ->
        case File.open(path, [:append, :utf8]) do
          {:ok, io_device} -> {:ok, io_device, get_inode(path)}
          other -> other
        end
      other -> other
    end
  end

  @spec get_inode(String.t) :: term | nil
  defp get_inode(path) do
    case File.stat(path) do
      {:ok, %File.Stat{inode: inode}} -> inode
      {:error, _} -> nil
    end
  end

  @spec configure(atom, map()) :: %{}
  defp configure(name, opts) do
    state = %{name: nil, path: nil, io_device: nil, inode: nil, level: nil, format: nil, metadata: nil, json_encoder: nil}
    configure(name, opts, state)
  end
  defp configure(name, opts, state) do
    env = Application.get_env(:logger, name, [])
    opts = Keyword.merge(env, opts)
    Application.put_env(:logger, name, opts)

    level = Keyword.get(opts, :level, :info)
    metadata = Keyword.get(opts, :metadata, [])
    format = Keyword.get(opts, :format, @log_default_format)
             |> Logger.Formatter.compile()
    path = Keyword.get(opts, :path)
    json_encoder = Keyword.get(opts, :json_encoder, nil)

    %{state | name: name, path: path, format: format, level: level, metadata: metadata, json_encoder: json_encoder}
  end


    defp format(level, message, timestamps, metadata, %{format: format, metadata: metadata_keys, json_encoder: json_encoder} = state) do
      if(is_nil(json_encoder)) do
        Logger.Formatter.format(format, level, message, timestamps, reduce_metadata(metadata, metadata_keys))
      else
        format_json(level, message, timestamps, metadata, state)
      end
  end
  defp format_json(level, message, timestamps, metadata, %{metadata: metadata_keys, json_encoder: json_encoder}) do
    metadata_map = reduce_metadata(metadata, metadata_keys)
                   |> Enum.into(%{})
    json_encoder.encode!(Map.merge(%{level: level, message: IO.iodata_to_binary(message), time: format_time(timestamps)}, metadata_map)) <> "\n"
  end

  defp format_time({date, time}) do
    fmt_date = Logger.Utils.format_date(date)
              |> IO.iodata_to_binary()
    fmt_time = Logger.Utils.format_time(time)
              |> IO.iodata_to_binary()
    "#{fmt_date} #{fmt_time}"
  end

  defp rename_file(path, keep) do
    File.rm("#{path}.#{keep}")
    _ = Enum.map(keep-1..1, &(File.rename("#{path}.#{&1}", "#{path}.#{&1+1}")))
    case File.rename(path, "#{path}.1") do
      :ok -> false
      _   -> true
    end
  end

  # for log rotate.
  defp rotate(path, %{max_bytes: max_bytes, keep: keep }) when is_integer(max_bytes) and is_integer(keep) and keep > 0 do
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
  defp rotate(_path, _), do: true

  @spec reduce_metadata([atom], [atom]) :: [{atom, atom}]
  defp reduce_metadata(metadata, keys) do
    reduce_metadata_ref(metadata, [], keys)
  end
  defp reduce_metadata_ref(_metadata, ret, []) do
    ret
  end
  defp reduce_metadata_ref(metadata, ret, [key | keys]) do
    case Map.fetch(metadata, key) do
      {:ok, value} ->
        reduce_metadata_ref(metadata, [{key, value} | ret], keys)
      :error ->
        reduce_metadata_ref(metadata, ret, keys)
    end
  end
end
