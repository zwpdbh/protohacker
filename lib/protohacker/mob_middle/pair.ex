defmodule Protohacker.MobMiddle.Pair do
  use GenServer

  def start_link(upstream_socket, client_socket) do
    GenServer.start_link(__MODULE__, {upstream_socket, client_socket})
  end

  defstruct [:upstream_socket, :client_socket]

  @impl true
  def init({upstream_socket, client_socket}) do
    state = %__MODULE__{upstream_socket: upstream_socket, client_socket: client_socket}

    {:ok, state, {:continue, :accept}}
  end

  @impl true
  def handle_continue(:accept, %__MODULE__{} = state) do
    {:noreply, state}
  end
end
