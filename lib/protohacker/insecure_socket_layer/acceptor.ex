defmodule Protohacker.InsecureSocketLayer.Acceptor do
  require Logger
  use Task, restart: :transient

  @port 5008

  def start_link([] = _opts) do
    Task.start_link(__MODULE__, :run, [:no_args])
  end

  def run(:no_args) do
    listen_options =
      [mode: :binary, active: :once, reuseaddr: true]

    case :gen_tcp.listen(@port, listen_options) do
      {:ok, listen_socket} ->
        Logger.debug("start insecure socket layer server at port: #{inspect(@port)}")
        accept_loop(listen_socket)

      [:error, reason] ->
        raise "failed to listen on port #{inspect(@port)}, reason: #{inspect(reason)}"
    end
  end

  defp accept_loop(listen_socket) do
    case :gen_tcp.accept(listen_socket) do
      {:error, reason} ->
        raise "failed to accept connectio, reason: #{inspect(reason)}"

      {:ok, socket} ->
        Protohacker.InsecureSocketLayer.ConnectionSupervisor.start_child(socket)
        accept_loop(socket)
    end
  end
end
