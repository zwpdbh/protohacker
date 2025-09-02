defmodule Protohacker.MobMiddleV2.Connection do
  require Logger
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

  @impl true
  def handle_info({:tcp, socket, data}, %__MODULE__{socket: socket} = state) do
    :ok = :inet.setopts(socket, active: :once)
    Logger.debug("->> received data: #{inspect(data)}")

    {:noreply, state}
  end

  @impl true
  def handle_info({:tco_error, socket, reason}, %__MODULE__{socket: socket} = state) do
    Logger.error("->> received tcp error: #{inspect(reason)}")

    :gen_tcp.close(socket)
    {:stop, {:normal, reason}, state}
  end

  @impl true
  def handle_info({:tcp_closed, socket}, %__MODULE__{socket: socket} = state) do
    Logger.warning("->> tcp connection closed")
    {:stop, {:normal, :tcp_closed}, state}
  end
end
