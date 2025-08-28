defmodule Protohacker.SpeedDaemon.Client do
  require Logger
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  defstruct [
    :role,
    :socket,
    :buffer,
    :supervisor,
    :camera,
    :dispatcher
  ]

  @impl true
  def init(opts) do
    socket = Keyword.fetch!(opts, :socket)
    supervisor = Keyword.fetch!(opts, :supervisor)

    :ok = :inet.setopts(socket, active: :once) |> dbg()

    {:ok, %__MODULE__{socket: socket, buffer: <<>>, supervisor: supervisor}}
  end

  @impl true
  def handle_info(
        {:tcp, _socket, <<_type, _rest::binary>> = packet},
        %__MODULE__{buffer: buffer} = state
      ) do
    state |> dbg()

    case Protohacker.SpeedDaemon.Message.decode(buffer <> packet) do
      {:ok, :incomplete, data} ->
        :ok = :inet.setopts(state.socket, active: :once)
        {:noreply, %{state | buffer: data}}

      {:ok, %Protohacker.SpeedDaemon.Message.IAmCamera{} = camera, remaining} ->
        {:ok, _pid} = ensure_ticket_generator_started(camera.road, state.supervisor)

        :ok = :inet.setopts(state.socket, active: :once)
        {:noreply, %{state | buffer: remaining, role: :camera, camera: camera}}

      {:ok, %Protohacker.SpeedDaemon.Message.IAmDispatcher{} = dispatcher, remaining} ->
        for each_road <- dispatcher.roads do
          :ok = Phoenix.PubSub.subscribe(:speed_daemon, "ticket_generated_road_#{each_road}")
        end

        :ok = :inet.setopts(state.socket, active: :once)
        {:noreply, %{state | buffer: remaining, role: :dispatcher, dispatcher: dispatcher}}

      {:ok, %Protohacker.SpeedDaemon.Message.WantHeartbeat{interval: interval}, remaining} ->
        if interval > 0 do
          # Start heartbeat
          Protohacker.SpeedDaemon.HeartbeatManager.start_heartbeat(
            interval,
            state.socket
          )
        else
          # Cancel heartbeat
          Protohacker.SpeedDaemon.HeartbeatManager.cancel_heartbeat(state.socket)
        end

        :ok = :inet.setopts(state.socket, active: :once)
        {:noreply, %{state | buffer: remaining}}

      {:ok, %Protohacker.SpeedDaemon.Message.Plate{} = plate, remaining} ->
        with :camera <- state.role,
             camera <- state.camera,
             true <- not is_nil(camera) do
          :ok =
            Phoenix.PubSub.broadcast!(
              :speed_daemon,
              "camera_road_#{camera.road}",
              %{
                plate: plate.plate,
                timestamp: plate.timestamp,
                road: camera.road,
                mile: camera.mile,
                limit: camera.limit
              }
            )
        else
          _ ->
            Logger.warning("->> received plate info, but its state is: #{inspect(state)}")
        end

        :ok = :inet.setopts(state.socket, active: :once)
        {:noreply, %{state | buffer: remaining}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_info({:tcp_closed, _socket}, state) do
    state |> dbg()
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:tcp_error, _socket, reason}, state) do
    state |> dbg()

    {:stop, reason, state}
  end

  # In TicketDispatcher.ex
  @impl true
  def handle_info(
        %Protohacker.SpeedDaemon.Message.Ticket{} = ticket,
        %__MODULE__{role: :dispatcher, dispatcher: dispatcher} = state
      ) do
    # Only send if this dispatcher is responsible for the ticket's road
    if ticket.road in dispatcher.roads do
      ticket_packet = Protohacker.SpeedDaemon.Message.Ticket.encode(ticket)

      case :gen_tcp.send(state.socket, ticket_packet) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning("Failed to send ticket to dispatcher: #{inspect(reason)}")
          # Ticket lost, per spec
      end
    end

    {:noreply, state}
  end

  @impl true
  def terminate(reason, %__MODULE__{} = state) do
    state |> dbg()
    :gen_tcp.close(state.socket)

    Logger.info(
      "->> #{__MODULE__} terminating with reason: #{inspect(reason)} and state: #{inspect(state)}"
    )

    :ok
  end

  defp ensure_ticket_generator_started(road, supervisor) do
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
