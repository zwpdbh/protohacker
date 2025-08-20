defmodule Protohacker.MeansToEnd do
  @moduledoc """
  https://protohackers.com/problem/2
  """

  use GenServer

  @port 3005

  def start_link([] = _opts) do
    GenServer.start_link(__MODULE__, :no_state)
  end

  defstruct [
    :listen_socket
  ]

  @impl true
  def init(:no_state) do
    case :gen_tcp.listen(@port,
           mode: :binary,
           active: false,
           reuseaddr: true,
           exit_on_close: false
         ) do
      {:ok, listen_socket} ->
        {:ok, %__MODULE__{listen_socket: listen_socket}, {:continue, :accept}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:accept, %__MODULE__{} = state) do
    case :gen_tcp.accept(state.listen_socket) do
      {:error, reason} ->
        {:stop, reason}

      {:ok, socket} ->
        Task.start_link(fn -> handle_connection_loop(socket) end)
        {:noreply, state, {:continue, :accept}}
    end
  end

  defp handle_connection_loop(_socket) do
    :todo
  end
end
