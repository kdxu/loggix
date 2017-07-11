defmodule Loggix do

  @moduledoc"""
  """

  use GenServer

  @log_default_format "$time $metadata [$level] $message\n"

  defmodule State do
    defstruct [:name, :path, :io_device, :inode, :format, :level]
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

  def handle_call({level, _gl, {Logger, message, timestamps, metadata}}, state) do
    write_log(level, message, timestamps, metadata, state)
  end

  def handle_call(:flush, state) do
    {:ok, state}
  end

  defp write_log(_l, _message, _timestamps, _metadata, %State{path: nil} = state) do
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
  defp write_log(level, message, timestamps, metadata, %State{path: path, io_device: io_device} = state) when is_binary(path) do
    output = format(level, message, timestamps, metadata, state)
    IO.write(io_device, output)
    {:ok, state}
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

  defp get_inode(path) do
    case File.stat(path) do
      {:ok, %File.Stat{inode: inode}} -> inode
      {:error, _} -> nil
    end
  end

  defp initialize(name, opts) do
    initialize(name, opts, %State{})
  end
  defp initialize(name, opts, state) do
    env = Application.get_env(:logger, name, [])
    opts = Map.merge(env, opts)
    Application.put_env(:logger, name, opts)

    level           = Map.get(opts, :level)
    format_opts     = Map.get(opts, :format, @log_default_format)
    format          = Logger.Formatter.compile(format_opts)
    path            = Map.get(opts, :path)

    %State{state | name: name, path: path, format: format, level: level}
  end

  defp format(level, message, timestamps, metadata, %{format: format}) do
    Logger.Formatter.format(format, level, message, timestamps, metadata)
  end
end
