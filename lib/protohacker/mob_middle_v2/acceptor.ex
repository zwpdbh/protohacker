defmodule Protohacker.MobMiddleV2.Acceptor do
  use Task, restart: :transient

  def start_lin([] = _opts) do
    Task.start_link(__MODULE__, :run, [])
  end

  def run do
    case :gen_tcp.listen(Protohacker.MobMiddle.port(), [
           :binary,
           ifaddr: {0, 0, 0, 0},
           active: :once,
           reuseaddr: true
         ]) do
      {:ok, listen_socket} ->
        accept_loop(listen_socket)

      {:error, reason} ->
        raise " failed to listen on port #{Protohacker.MobMiddle.port()}, reason: #{inspect(reason)}"
    end
  end

  defp accept_loop(listen_socket) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, socket} ->
        Protohacker.MobMiddleV2.ConnectionSupervisor.start_child(socket)
        accept_loop(listen_socket)

      {:error, reason} ->
        raise " failed to accept connection: #{inspect(reason)}"
    end
  end
end
