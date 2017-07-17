defmodule Loggix do

  @moduledoc"""
  Loggix
  ----
  A custom implementation for Elixir Logger moduale.
  - Using GenEvent for handle log events.

  """

  use GenEvent

  #####################
  # type annotations. #
  #####################
  @type path  :: String.t
  @type level :: Logger.level
  @type metadata :: [atom]
  @type format :: String.t

  @log_default_format "$time $metadata [$level] $message\n"

  defmodule State do
    defstruct [:name, :path, :io_device, :inode, :format, :level, :metadata]
  end

  def init({__MODULE__, name}) do
    {:ok, initialize(name, %{})}
  end

  def handle_call({:initialize, opts}, %State{name: name} = state) do
    {:ok, :ok, initialize(name, opts, state)}
  end

  def handle_call(:path, %{path: path} = state) do
    {:ok, {:ok, path}, state}
  end

  def handle_event({level, _gl, {Logger, message, timestamps, metadata}}, %{level: min_level} = state) do
    case Logger.compare_levels(level, min_level) do
      :lt ->
        write_log(level, message, timestamps, metadata, state)
      _ ->
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
        {:ok, state} =  write_log(level, message, timestamps, metadata, %State{state | io_device: io_device, inode: inode})
        {:ok, state}
      _ ->
        {:ok, state}
    end
  end
  defp write_log(level, message, timestamps, metadata, %State{path: path, io_device: io_device, inode: inode} = state) when is_binary(path) do
    if inode == nil do
      write_log(level, message, timestamps, metadata, %State{state | io_device: nil})
      File.close(io_device)
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

  @spec get_inode(String.t) :: File.Stat.t | nil
  defp get_inode(path) do
    case File.stat(path) do
      {:ok, %File.Stat{inode: inode}} -> inode
      {:error, _} -> nil
    end
  end

  @spec initialize(atom, map()) :: %State{}
  defp initialize(name, opts) do
    initialize(name, opts, %State{})
  end
  defp initialize(name, opts, state) do
    env = Application.get_env(:logger, name, %{})
    opts = Map.merge(env, opts)
    Application.put_env(:logger, name, opts)

    level = Map.get(opts, :level)
    metadata = Map.get(opts, :metadata, [])
    format_opts = Map.get(opts, :format, @log_default_format)
    format  = Logger.Formatter.compile(format_opts)
    path = Map.get(opts, :path)

    %State{state | name: name, path: path, format: format, level: level, metadata: metadata}
  end

  defp format(level, message, timestamps, metadata, %{format: format, metadata: metadata_keys}) do
    Logger.Formatter.format(format, level, message, timestamps, reduce_metadata(metadata, metadata_keys))
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
