defmodule Protohacker.SpeedDaemonV2.Connection do
  use GenServer

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
end
