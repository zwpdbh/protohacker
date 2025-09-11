defmodule Protohacker.LineReversal.Acceptor do
  alias Protohacker.LineReversal.LRCP
  require Logger
  use Task, restart: :transient

  # @port 5006

  def start_link(options) when is_list(options) do
    ip = Keyword.fetch!(options, :ip)
    port = Keyword.fetch!(options, :port)

    Task.start_link(__MODULE__, :run, [ip, port])
  end

  def run(ip, port) when is_tuple(ip) and is_integer(port) do
    case LRCP.listen(ip, port) do
      {:ok, %LRCP.ListenSocket{} = listen_socket} ->
        accept_loop(listen_socket)

      {:error, reason} ->
        raise "failed to start LRCP listen socket on port #{port}: #{inspect(reason)}"
    end
  end

  defp accept_loop(listen_socket) do
    case LRCP.accept(listen_socket) do
      {:ok, socket} ->
        # {:ok, handler} = Connection.start_link(socket)
        # :ok = LRCP.controlling_process(socket, handler)
        Protohacker.LineReversal.ConnectionSupervisor.start_child(socket)
        accept_loop(listen_socket)

      {:error, reason} ->
        raise "failed to accept LRCP connection: #{inspect(reason)}"
    end
  end
end
