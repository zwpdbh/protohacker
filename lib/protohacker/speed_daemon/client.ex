defmodule Protohacker.SpeedDaemon.Client do
  require Logger
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      # ← Critical: don't restart after client disconnects
      restart: :temporary
    }
  end

  defstruct [
    :role,
    :socket,
    :buffer,
    :supervisor,
    :camera,
    :dispatcher,
    :task_supervisor,
    :myself
  ]

  @impl true
  def init(opts) do
    socket = Keyword.fetch!(opts, :socket)
    supervisor = Keyword.fetch!(opts, :supervisor)

    {:ok,
     %__MODULE__{
       socket: socket,
       buffer: <<>>,
       supervisor: supervisor,
       myself: self()
     }, {:continue, :recv}}
  end

  @impl true
  def handle_continue(:recv, %__MODULE__{} = state) do
    Task.start(fn ->
      recv_loop(state.myself, state.socket, "")
    end)

    {:noreply, state}
  end

  defp recv_loop(myself, socket, buffer) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, packet} ->
        Logger.info(
          "->> #{inspect(myself)} #{inspect(socket)} received: #{inspect(packet)}, current_buffer: #{inspect(buffer)}"
        )

        decode_packet(myself, socket, buffer <> packet)

      {:error, reason} ->
        send(myself, {:recv_error, reason})
    end
  end

  # REVIEW: how to parse network data
  defp decode_packet(myself, socket, packet) do
    case Protohacker.SpeedDaemon.Message.decode(packet) do
      {:ok, :incomplete, data} ->
        recv_loop(myself, socket, data)

      {:ok, %Protohacker.SpeedDaemon.Message.IAmCamera{} = camera, remaining} ->
        send(myself, {:i_am_camera, camera})
        decode_packet(myself, socket, remaining)

      {:ok, %Protohacker.SpeedDaemon.Message.IAmDispatcher{} = dispatcher, remaining} ->
        send(myself, {:i_am_dispatcher, dispatcher})
        decode_packet(myself, socket, remaining)

      {:ok, %Protohacker.SpeedDaemon.Message.WantHeartbeat{interval: interval}, remaining} ->
        send(myself, {:want_heartbeat, interval})
        decode_packet(myself, socket, remaining)

      {:ok, %Protohacker.SpeedDaemon.Message.Plate{} = plate, remaining} ->
        send(myself, {:plate, plate})
        decode_packet(myself, socket, remaining)

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_info({:recv_error, reason}, state) do
    {:stop, {:shutdown, reason}, state}
  end

  @impl true
  def handle_info({:i_am_camera, camera}, state) do
    {:noreply, %{state | role: :camera, camera: camera}}
  end

  @impl true
  def handle_info({:i_am_dispatcher, dispatcher}, state) do
    for each_road <- dispatcher.roads do
      :ok = Phoenix.PubSub.subscribe(:speed_daemon, "ticket_generated_road_#{each_road}")
    end

    {:noreply, %{state | role: :dispatcher, dispatcher: dispatcher}}
  end

  @impl true
  def handle_info({:plate, plate}, %__MODULE__{} = state) do
    with :camera <- state.role,
         camera <- state.camera,
         true <- not is_nil(camera) do
      :ok =
        Phoenix.PubSub.broadcast!(
          :speed_daemon,
          "camera",
          %{
            plate: plate.plate,
            timestamp: plate.timestamp,
            road: camera.road,
            mile: camera.mile,
            limit: camera.limit
          }
        )

      {:noreply, state}
    else
      _ ->
        {:stop, "only camera could received plate info", state}
    end
  end

  @impl true
  def handle_info({:want_heartbeat, interval}, %__MODULE__{} = state) do
    if interval > 0 do
      # Start heartbeat
      case Protohacker.SpeedDaemon.HeartbeatManager.start_heartbeat(
             interval,
             state.socket
           ) do
        {:ok, _pid} ->
          {:noreply, state}

        {:error, _existing_pid} ->
          msg =
            "multiple WantHeartbeat messages on a single connection"
            |> Protohacker.SpeedDaemon.Message.Error.encode()

          :ok = :gen_tcp.send(state.socket, msg)

          {:stop, {:shutdown, "multiple want_heartbeat for client: #{inspect(state.socket)}"},
           state}
      end
    else
      # Cancel heartbeat
      Protohacker.SpeedDaemon.HeartbeatManager.cancel_heartbeat(state.socket)
      {:noreply, state}
    end
  end

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
          Logger.info("->> sent ticket: #{inspect(ticket)}")

        {:error, reason} ->
          # Ticket lost, per spec
          Logger.warning("->> failed to send ticket to dispatcher: #{inspect(reason)}")
      end
    end

    {:noreply, state}
  end

  @impl true
  def terminate(reason, %__MODULE__{} = state) do
    Logger.warning("->> Client terminate, reason: #{inspect(reason)}, state: #{inspect(state)}")

    :gen_tcp.close(state.socket)
    :ok
  end

  # defp ensure_ticket_generator_started(road, supervisor) do
  #   ticket_generator_registered = Registry.lookup(TicketGeneratorRegistry, road)

  #   case ticket_generator_registered do
  #     [{pid, _value}] ->
  #       {:ok, pid}

  #     [] ->
  #       case DynamicSupervisor.start_child(
  #              supervisor,
  #              {Protohacker.SpeedDaemon.TicketGenerator, road: road}
  #            ) do
  #         {:ok, pid} -> {:ok, pid}
  #         {:error, {:already_started, pid}} -> {:ok, pid}
  #       end
  #   end
  # end
end
