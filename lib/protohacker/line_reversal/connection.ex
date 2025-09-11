defmodule Protohacker.LineReversal.Connection do
  alias Protohacker.LineReversal.LRCP

  require Logger
  use GenServer

  def start_link(socket) do
    GenServer.start_link(__MODULE__, socket)
  end

  defstruct [
    :socket,
    buffer: <<>>
  ]

  @impl true
  def init(socket) do
    Logger.debug("connection started: #{inspect(socket)}")
    state = %__MODULE__{socket: socket}
    {:ok, state}
  end

  @impl true
  def handle_info({:lrcp, socket, data}, %__MODULE__{socket: socket} = state) do
    Logger.debug("received LRCP data: #{inspect(data)}")
    state = update_in(state.buffer, fn b -> b <> data end)
    state = handle_new_data(state)

    {:noreply, state}
  end

  def handle_info({:lrcp_error, socket, reason}, %__MODULE__{socket: socket} = state) do
    Logger.error("closing connection due to error: #{inspect(reason)}")
    {:stop, :normal, state}
  end

  def handle_info({:lrcp_closed, socket}, %__MODULE__{socket: socket} = state) do
    Logger.debug("Connection closed")
    {:stop, :normal, state}
  end

  # ------------------------
  # Helpers
  # ------------------------
  def handle_new_data(%__MODULE__{} = state) do
    case String.split(state.buffer, "\n", parts: 2) do
      [line, rest] ->
        LRCP.send(state.socket, String.reverse(line) <> "\n")
        handle_new_data(put_in(state.buffer, rest))

      [_no_line_yet] ->
        state
    end
  end
end
