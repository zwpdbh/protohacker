defmodule Protohacker.LineReversal.Connection do
  use GenServer

  def start_link(socket) do
    GenServer.start_link(__MODULE__, socket)
  end

  defstruct [
    :socket
  ]

  @impl true
  def init(socket) do
    state = %__MODULE__{socket: socket}
    {:ok, state}
  end
end
