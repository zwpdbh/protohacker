defmodule Protohacker.EchoServer do
  require Logger
  use GenServer
  @port 5000

  def start_link([] = _opts) do
    GenServer.start_link(__MODULE__, :no_state)
  end

  defstruct [
    :listen_socket
  ]

  @impl true
  def init(:no_state) do
    listen_options = [
      mode: :binary,
      active: false,
      reuseaddr: true,
      exit_on_close: false
    ]

    case(:gen_tcp.listen(@port, listen_options)) do
      {:ok, listen_socket} ->
        Logger.info("Start echo server on port: #{@port}")

        state = %__MODULE__{listen_socket: listen_socket}
        {:ok, state, {:continue, :accept}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:accept, %__MODULE__{} = state) do
    case :gen_tcp.accept(state.listen_socket) do
      {:ok, socket} ->
        Task.start(fn -> handle_connection(socket) end)
        {:noreply, state, {:continue, :accept}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  defp handle_connection(socket) do
    Logger.info("->> handle_connection: #{inspect(socket)}")

    case recv_until_closed(socket, _buffer = "") do
      {:ok, data} ->
        Logger.info("->> echo back data: #{inspect(data)}")
        :gen_tcp.send(socket, data)

      {:error, reason} ->
        Logger.error("->> failed to receive data: #{inspect(reason)}")
    end

    :gen_tcp.close(socket)
  end

  defp recv_until_closed(socket, buffer) do
    case :gen_tcp.recv(socket, 0, 10_000) do
      {:ok, data} ->
        Logger.info("->> received data: #{inspect(data)}")
        recv_until_closed(socket, buffer <> data)

      {:error, :closed} ->
        {:ok, buffer}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
