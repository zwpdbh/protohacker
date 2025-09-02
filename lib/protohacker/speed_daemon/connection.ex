defmodule Protohacker.SpeedDaemon.Connection do
  require Logger
  use GenServer

  def start_link(socket) do
    GenServer.start_link(__MODULE__, socket)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary
    }
  end

  defstruct [
    :socket,
    :role,
    :buffer,
    :camera,
    :dispatcher,
    :heartbeat_supervisor
  ]

  @impl true
  def init(socket) do
    {:ok, sup} = Task.Supervisor.start_link(max_children: 1)
    {:ok, %__MODULE__{role: nil, buffer: "", socket: socket, heartbeat_supervisor: sup}}
  end

  @impl true
  def handle_info(
        {:tcp, socket, packet},
        %__MODULE__{socket: socket, buffer: buffer} = state
      ) do
    :ok = :inet.setopts(socket, active: :once)
    {:noreply, %__MODULE__{state | buffer: buffer <> packet}, {:continue, :process_packet}}
  end

  # Handle event from subscrition for generated ticket
  @impl true
  def handle_info(
        %Protohacker.SpeedDaemon.Message.Ticket{} = ticket,
        %__MODULE__{role: :dispatcher, socket: socket} = state
      ) do
    Protohacker.SpeedDaemon.TicketManager.send_ticket_to_socket(ticket, socket)
    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp_error, socket, reason}, %__MODULE__{socket: socket} = state) do
    {:stop, {:normal, reason}, state}
  end

  @impl true
  def handle_info({:tcp_closed, socket}, %__MODULE__{socket: socket} = state) do
    {:stop, {:normal, :tcp_closed}, state}
  end

  @impl true
  def handle_continue(
        :process_packet,
        %__MODULE__{socket: socket, buffer: buffer, heartbeat_supervisor: sup} = state
      ) do
    case Protohacker.SpeedDaemon.Message.decode(buffer) do
      {:ok, :incomplete, data} ->
        {:noreply, %{state | buffer: data}}

      {:ok, %Protohacker.SpeedDaemon.Message.WantHeartbeat{interval: interval}, remaining} ->
        case Task.Supervisor.start_child(sup, fn -> do_heartbeat(interval, socket) end) do
          {:ok, _pid} ->
            {:noreply, %{state | buffer: remaining}, {:continue, :process_packet}}

          {:error, :max_children} ->
            msg_bytes =
              "multiple heartbeat"
              |> Protohacker.SpeedDaemon.Message.Error.encode()

            :gen_tcp.send(socket, msg_bytes)
            {:stop, {:normal, :multiple_heartbeat}, state}
        end

      {:ok, %Protohacker.SpeedDaemon.Message.IAmCamera{} = camera, remaining} ->
        {:noreply, %{state | buffer: remaining, role: :camera, camera: camera},
         {:continue, :process_packet}}

      {:ok, %Protohacker.SpeedDaemon.Message.IAmDispatcher{} = dispatcher, remaining} ->
        for each_road <- dispatcher.roads do
          :ok = Phoenix.PubSub.subscribe(:speed_daemon, "ticket_generated_road_#{each_road}")
        end

        Protohacker.SpeedDaemon.TicketManager.dispatcher_is_online(dispatcher)

        {:noreply, %{state | buffer: remaining, role: :dispatcher, dispatcher: dispatcher},
         {:continue, :process_packet}}

      {:ok, %Protohacker.SpeedDaemon.Message.Plate{} = plate, remaining} ->
        :ok =
          Protohacker.SpeedDaemon.TicketGenerator.record_plate(%{
            plate: plate.plate,
            timestamp: plate.timestamp,
            road: state.camera.road,
            mile: state.camera.mile,
            limit: state.camera.limit
          })

        {:noreply, %{state | buffer: remaining}, {:continue, :process_packet}}

      {:error, reason} ->
        {:stop, reason, state}
    end
  end

  defp do_heartbeat(interval, socket) do
    if interval > 0 do
      :gen_tcp.send(
        socket,
        Protohacker.SpeedDaemon.Message.Heartbeat.encode(
          %Protohacker.SpeedDaemon.Message.Heartbeat{}
        )
      )

      :timer.sleep(interval * 100)
      do_heartbeat(interval, socket)
    else
      :ok
    end
  end
end
