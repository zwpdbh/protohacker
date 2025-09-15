defmodule Protohacker.InsecureSocketLayer.Connection do
  use GenServer, restart: :temporary

  def start_link(socket) do
    GenServer.start_link(__MODULE__, socket)
  end

  defstruct [
    :socket
  ]

  @impl true
  def init(socket) do
    {:ok, %__MODULE__{socket: socket}}
  end

  @impl true
  def handle_info({:tcp, socket, _data}, %__MODULE__{socket: socket} = state) do
    :ok = :inet.setopts(socket, active: :once)
    :todo

    {:noreply, state}
  end
end
