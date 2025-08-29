defmodule Protohacker.SpeedDaemonV2.Acceptor do
  require Logger
  # This makes this module could be monitored by a Supervisor
  use Task, restart: :transient

  @port 5005

  def start_link([] = _opts) do
    Task.start_link(__MODULE__, :run, [:no_args])
  end

  def run(:no_args) do
    listen_options =
      [
        mode: :binary,
        active: :once,
        reuseaddr: true
        # ifaddr: {0, 0, 0, 0}
      ]

    case :gen_tcp.listen(@port, listen_options) do
      {:ok, listen_socket} ->
        Logger.info("->> start speed daemon server at port: #{@port}")
        accept_loop(listen_socket)

      {:error, reason} ->
        raise "->> failed to listen on port: #{@port}, reason: #{inspect(reason)}"
    end
  end

  defp accept_loop(listen_socket) do
    case :gen_tcp.accept(listen_socket) do
      {:error, reason} ->
        raise "->> faied to accept connection, reason: #{inspect(reason)}"

      {:ok, socket} ->
        Protohacker.SpeedDaemonV2.ConnectionSupervisor.start_child(socket)
        accept_loop(listen_socket)
    end
  end
end
