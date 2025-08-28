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
        Task.Supervisor.start_child(state.task_supervisor, fn ->
          handle_accepted_connection(socket, state.supervisor)
        end)

        {:noreply, state, {:continue, :accept}}

      {:error, reason} ->
        :gen_tcp.close(state.listen_socket)
        {:stop, reason}
    end
  end

  defp handle_accepted_connection(socket, supervisor) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, packet} ->
        case(Protohacker.SpeedDaemon.Message.decode(packet)) do
          {:ok, %Protohacker.SpeedDaemon.Message.IAmCamera{} = camera, remaining} ->
            {:ok, _pid} = ensure_ticket_generator_started(camera.road, supervisor)

            {:ok, _pid} =
              DynamicSupervisor.start_child(
                supervisor,
                {Protohacker.SpeedDaemon.Camera,
                 socket: socket, camera: camera, remaining: remaining, supervisor: supervisor}
              )

          {:ok, %Protohacker.SpeedDaemon.Message.IAmDispatcher{} = dispatcher, remaining} ->
            {:ok, _pid} =
              DynamicSupervisor.start_child(
                supervisor,
                {Protohacker.SpeedDaemon.TicketDispatcher,
                 socket: socket, dispatcher: dispatcher, remaining: remaining}
              )

          {:ok, %Protohacker.SpeedDaemon.Message.WantHeartbeat{interval: interval}, ""} ->
            if interval > 0 do
              # Start heartbeat
              Protohacker.SpeedDaemon.HeartbeatManager.start_heartbeat(
                interval,
                socket
              )
              |> dbg()
            else
              # Cancel heartbeat
              Protohacker.SpeedDaemon.HeartbeatManager.cancel_heartbeat(socket)
            end

          other_message ->
            Logger.warning(
              "->> received unexpected other message: #{inspect(other_message)} from #{__MODULE__}"
            )

            message =
              "illegal msg"
              |> Protohacker.SpeedDaemon.Message.Error.encode()

            :gen_tcp.send(socket, message)
            :gen_tcp.close(socket)
        end

      {:error, reason} ->
        reason |> dbg()
        :gen_tcp.close(socket)
    end
  end

  def ensure_ticket_generator_started(road, supervisor) do
    ticket_generator_registered = Registry.lookup(TicketGeneratorRegistry, road)

    case ticket_generator_registered do
      [{pid, _value}] ->
        {:ok, pid}

      [] ->
        case DynamicSupervisor.start_child(
               supervisor,
               {Protohacker.SpeedDaemon.TicketGenerator, road: road}
             ) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
        end
    end
  end
end
