defmodule Protohacker.SpeedDaemon.Connection do
  require Logger
  use GenServer, restart: :temporary

  def start_link(socket) do
    GenServer.start_link(__MODULE__, socket)
  end

  defstruct [
    :socket,
    :role,
    :buffer,
    :camera,
    :dispatcher,
    :heartbeat_ref
  ]

  @impl true
  def init(socket) do
    {:ok, %__MODULE__{role: nil, buffer: "", socket: socket}}
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
    Logger.error(" Connection closed because of error: #{inspect(reason)}")
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:tcp_closed, socket}, %__MODULE__{socket: socket} = state) do
    {:stop, :normal, state}
  end

  def handle_info(:send_heartbeat, %__MODULE__{} = state) do
    msg_packet =
      %Protohacker.SpeedDaemon.Message.Heartbeat{} |> Protohacker.SpeedDaemon.Message.encode()

    :gen_tcp.send(state.socket, msg_packet)
    {:noreply, state}
  end

  @impl true
  def handle_continue(
        :process_packet,
        %__MODULE__{buffer: buffer} = state
      ) do
    case Protohacker.SpeedDaemon.Message.decode(buffer) do
      :incomplete ->
        {:noreply, %{state | buffer: buffer}}

      {:ok, %Protohacker.SpeedDaemon.Message.WantHeartbeat{interval: interval}, remaining} ->
        interval_in_ms = interval * 10

        if state.heartbeat_ref do
          :timer.cancel(state.heartbeat_ref)
        end

        if interval > 0 do
          {:ok, heartbeat_ref} = :timer.send_interval(interval_in_ms, :send_heartbeat)

          {:ok, %__MODULE__{state | heartbeat_ref: heartbeat_ref, buffer: remaining},
           {:continue, :process_packet}}
        else
          {:ok, %__MODULE__{state | heartbeat_ref: nil, buffer: remaining},
           {:continue, :process_packet}}
        end

      {:ok, %Protohacker.SpeedDaemon.Message.IAmCamera{} = camera, remaining} ->
        {:noreply, %{state | buffer: remaining, role: :camera, camera: camera},
         {:continue, :process_packet}}

      {:ok, %Protohacker.SpeedDaemon.Message.IAmDispatcher{} = dispatcher, remaining} ->
        Logger.metadata(role: :dispatcher, info: "#{inspect(dispatcher)}")

        for each_road <- dispatcher.roads do
          :ok = Phoenix.PubSub.subscribe(:speed_daemon, "ticket_generated_road_#{each_road}")
          Logger.info(" subscribe topic: ticket_generated_road_#{each_road}")
        end

        :ok = Protohacker.SpeedDaemon.TicketManager.dispatcher_is_online(dispatcher)
        Logger.info(" let TicketManager know dispatcher is online")

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

      :error ->
        {:stop, :normal, state}
    end
  end
end
