defmodule Protohacker.SpeedDaemon do
  @moduledoc """

  """
  require Logger

  use GenServer

  defstruct [
    :listen_socket,
    :supervisor,
    :myself
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
        sup = DynamicSupervisor.start_link(strategy: :one_for_one)

        {:ok, %__MODULE__{listen_socket: listen_socket, supervisor: sup, myself: self()},
         {:continue, :accept}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:accept, %__MODULE__{} = state) do
    case :gen_tcp.accept(state.listen_socket) do
      {:ok, socket} ->
        Task.start(fn -> handle_connection(socket, state) end)

        {:noreply, state, {:continue, :accept}}

      {:error, reason} ->
        :gen_tcp.close(state.listen_socket)
        {:stop, reason}
    end
  end

  defp handle_connection(socket, %__MODULE__{} = state) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, message} ->
        case Protohacker.SpeedDaemon.Message.decode(message) do
          {:ok, %Protohacker.SpeedDaemon.Message.IAmCamera{} = camera, remaining} ->
            DynamicSupervisor.start_child(
              state.supervisor,
              {Protohacker.SpeedDaemon.Camera, camera: camera, remaining: remaining}
            )

          {:ok, %Protohacker.SpeedDaemon.Message.IAmDispatcher{} = dispatcher, remaining} ->
            DynamicSupervisor.start_child(
              state.supervisor,
              {Protohacker.SpeedDaemon.TicketDispatcher,
               dispatcher: dispatcher, remaining: remaining, socket: socket}
            )

          {:error, reason, _data} ->
            Logger.warning("->> first message received by
               #{__MODULE__} is unknown format: #{inspect(message)}, reason: #{inspect(reason)}")

            :gen_tcp.close(socket)
        end

      {:error, reason} ->
        Logger.warning("->> #{__MODULE__} handle_connection error: #{inspect(reason)}")
        :gen_tcp.close(socket)
    end
  end
end
