defmodule Protohacker.SpeedDaemon do
  @moduledoc """

  """

  use GenServer

  defstruct [
    :listen_socket,
    :supervisor
  ]

  @port 4004

  def port() do
    @port
  end

  def start_link([] = _opts) do
    GenServer.start_link(__MODULE__, :no_state)
  end

  @impl true
  def init(:no_state) do
    options = [
      mode: :binary,
      reuseaddr: true,
      exit_on_close: false,
      active: false
    ]

    case :gen_tcp.listen(@port, options) do
      {:ok, listen_socket} ->
        sup = Task.Supervisor.start_link(max_children: 100)

        {:ok, %__MODULE__{listen_socket: listen_socket, supervisor: sup}, {:continue, :accept}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:accept, %__MODULE__{} = state) do
    case :gen_tcp.accept(state.listen_socket) do
      {:ok, _socket} ->
        :handle_socket

        {:noreply, state, {:continue, :accept}}

      {:error, reason} ->
        {:stop, reason}
    end
  end
end
