defmodule Protohacker.SpeedDaemon do
  @moduledoc """

  """
  require Logger

  use GenServer

  defstruct [
    :listen_socket,
    :myself,
    :supervisor,
    :task_supervisor
  ]

  @port 5005

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

    with {:ok, listen_socket} <- :gen_tcp.listen(@port, options),
         {:ok, _pid} <- Registry.start_link(keys: :unique, name: TicketGeneratorRegistry),
         {:ok, sup} <- DynamicSupervisor.start_link(strategy: :one_for_one),
         {:ok, task_sup} <- Task.Supervisor.start_link(max_children: 100),
         {:ok, _pid} <- DynamicSupervisor.start_child(sup, {Phoenix.PubSub, name: :speed_daemon}),
         # Start HeartbeatManager as a child of our DynamicSupervisor
         {:ok, _heartbeat_manager_pid} <-
           DynamicSupervisor.start_child(sup, Protohacker.SpeedDaemon.HeartbeatManager) do
      Logger.info("->> start speed_daemon server at port: #{@port}")

      state = %__MODULE__{
        listen_socket: listen_socket,
        supervisor: sup,
        task_supervisor: task_sup,
        myself: self()
      }

      {:ok, state, {:continue, :accept}}
    else
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:accept, %__MODULE__{} = state) do
    case :gen_tcp.accept(state.listen_socket) do
      {:ok, socket} ->
        {:ok, _pid} =
          DynamicSupervisor.start_child(
            state.supervisor,
            {Protohacker.SpeedDaemon.Client, socket: socket, supervisor: state.supervisor}
          )

        {:noreply, state, {:continue, :accept}}

      {:error, reason} ->
        :gen_tcp.close(state.listen_socket)
        {:stop, reason}
    end
  end
end
