defmodule Protohacker.SpeedDaemon.TicketDispatcher do
  use GenServer

  require Logger

  def child_spec(opts) do
    %{
      id: __MODULE__,
      restart: :temporary,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  defstruct [
    :roads,
    :remaining,
    :socket,
    :supervisor,
    :myself
  ]

  def start_link(opts) do
    socket = Keyword.fetch!(opts, :socket)
    dispatcher = Keyword.fetch!(opts, :dispatcher)
    remaining = Keyword.fetch!(opts, :remaining)
    GenServer.start_link(__MODULE__, {socket, dispatcher, remaining})
  end

  @impl true
  def init({socket, %Protohacker.SpeedDaemon.Message.IAmDispatcher{} = dispatcher, remaining}) do
    {:ok, sup} = Task.Supervisor.start_link(max_children: 1)

    state =
      %__MODULE__{
        socket: socket,
        remaining: remaining,
        roads: dispatcher.roads,
        supervisor: sup,
        myself: self()
      }

    # Subscribe to ticket topics for each road
    for road <- dispatcher.roads do
      Phoenix.PubSub.subscribe(:speed_daemon, "ticket_generated_road_#{road}") |> dbg()
    end

    {:ok, state, {:continue, :accept}}
  end

  @impl true
  def handle_continue(:accept, %__MODULE__{} = state) do
    Task.Supervisor.start_child(state.supervisor, fn ->
      handle_connection_loop(state.socket, state.remaining, state.myself)
    end)

    {:noreply, state}
  end

  def handle_connection_loop(socket, remaining, myself) do
    case :gen_tcp.recv(socket, 0) |> dbg() do
      {:ok, packet} ->
        case Protohacker.SpeedDaemon.Message.decode((remaining <> packet) |> dbg()) do
          {:ok, message, remaining} ->
            case message do
              %Protohacker.SpeedDaemon.Message.WantHeartbeat{} = hb ->
                :ok =
                  Protohacker.SpeedDaemon.HeartbeatManager.start_heartbeat(hb.interval, socket)

                handle_connection_loop(socket, remaining, myself)

              other_message ->
                Logger.warning(
                  "->> TicketDispatcher receive other message: #{inspect(other_message)}"
                )

                handle_connection_loop(socket, remaining, myself)
            end

          error ->
            Logger.warning("->> decode message error: #{inspect(error)}")
            {:stop, error}

            message =
              "illegal msg"
              |> Protohacker.SpeedDaemon.Message.Error.encode()

            :gen_tcp.send(socket, message)
        end

      {:error, reason} ->
        {:stop, reason}
    end
  end

  # In TicketDispatcher.ex
  @impl true
  def handle_info(%Protohacker.SpeedDaemon.Message.Ticket{} = ticket, state) do
    # Only send if this dispatcher is responsible for the ticket's road
    if ticket.road in state.roads do
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
  def terminate(_reason, %__MODULE__{} = state) do
    if not is_nil(state.roads) do
      for each_road <- state.roads do
        Phoenix.PubSub.broadcast!(
          :speed_daemon,
          "ticket_dispatcher_road_#{each_road}",
          :dispatcher_offline
        )
      end
    end

    :gen_tcp.close(state.socket)
    :ok
  end
end
