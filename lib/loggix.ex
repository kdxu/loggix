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

  @doc"""
  # Loggix.State
    the main struct of GenEvent.
  """
  defmodule State do
    defstruct [name: nil, path: nil, io_device: nil, inode: nil, format: nil, level: nil, metadata: nil, json_encoder: nil]
  end

  def init({__MODULE__, name}) do
    {:ok, configure(name, [])}
  end

  def handle_call({:configure, opts}, %State{name: name} = state) do
    {:ok, :ok, configure(name, opts, state)}
  end

  def handle_call(:path, %{path: path} = state) do
    {:ok, {:ok, path}, state}
  end

  def handle_event({level, _gl, {Logger, message, timestamps, metadata}}, %State{level: min_level} = state) do
    if min_level == nil  || Logger.compare_levels(level, min_level) != :lt do
      write_log(level, message, timestamps, metadata, state)
    else
      {:ok, state}
    end
  end

  def handle_event(:flush, state) do
    {:ok, state}
  end

  defp write_log(_level, _message, _timestamps, _metadata, %State{path: nil} = state) do
    {:ok, state}
  end
  defp write_log(level, message, timestamps, metadata, %State{path: path, io_device: nil} = state) when is_binary(path) do
    case open_log(path) do
      {:ok, io_device, inode} ->
        write_log(level, message, timestamps, metadata, %State{state | io_device: io_device, inode: inode})
        {:ok, state}
      _ ->
        {:ok, state}
    end
  end
  defp write_log(level, message, timestamps, metadata, %State{path: path, io_device: io_device, inode: inode} = state) when is_binary(path) do
    if inode == nil || inode != get_inode(inode) do
      File.close(io_device)
      write_log(level, message, timestamps, metadata, %State{state | io_device: nil, inode: nil})
    else
      output = format(level, message, timestamps, metadata, state)
      IO.write(io_device, output)
      {:ok, state}
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

  @spec configure(atom, map()) :: %State{}
  defp configure(name, opts) do
    configure(name, opts, %State{})
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

    %State{state | name: name, path: path, format: format, level: level, metadata: metadata, json_encoder: json_encoder}
  end


  defp format(level, message, timestamps, metadata, %State{format: format, metadata: metadata_keys, json_encoder: nil}) do
    Logger.Formatter.format(format, level, message, timestamps, reduce_metadata(metadata, metadata_keys))
  end
  defp format(level, message, timestamps, metadata, %State{metadata: metadata_keys, json_encoder: json_encoder}) do
    json_encoder.encode!(Map.merge(%{level: level, message: IO.iodata_to_binary(message), time: format_time(timestamps)}, reduce_metadata(metadata, metadata_keys))) <> "\n"
  end

  defp format_time({date, time}) do
    fmt_date = Logger.Utils.format_date(date)
              |> IO.iodata_to_binary()
    fmt_time = Logger.Utils.format_time(time)
              |> IO.iodata_to_binary()
    "#{fmt_date} #{fmt_time}"
  end

  #############
  # Utilities #
  #############
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
