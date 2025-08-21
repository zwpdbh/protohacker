defmodule Protohacker.BudgetChat do
  @moduledoc """
  https://protohackers.com/problem/3
  """
  require Logger

  use GenServer

  @port 3007

  def port do
    @port
  end

  defstruct [
    :listen_socket
  ]

  def start_link([] = _opts) do
    GenServer.start_link(__MODULE__, :no_state)
  end

  @impl true
  def init(:no_state) do
    case :gen_tcp.listen(@port, reuseaddr: true, active: false, packet: :line) do
      {:ok, listen_socket} ->
        {:ok, %__MODULE__{listen_socket: listen_socket}, {:continue, :accept}}

      {:error, reason} ->
        Logger.error("#{__MODULE__} init failed: #{inspect(reason)}")
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

  defp handle_connection_loop(socket) do
    handle_connection_loop(socket)
  end
end
