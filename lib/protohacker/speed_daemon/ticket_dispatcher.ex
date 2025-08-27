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
    :myself,
    :remaining,
    :socket,
    :supervisor
  ]

  def start_link(opts) do
    socket = Keyword.fetch!(opts, :socket)
    sup = Keyword.fetch!(opts, :supervisor)
    GenServer.start_link(__MODULE__, {socket, sup})
  end

  @impl true
  def init({socket, sup}) do
    state = %__MODULE__{
      socket: socket,
      remaining: <<>>,
      supervisor: sup
    }

    :gen_tcp.controlling_process(socket, self())
    {:ok, state, {:continue, :accept}}
  end

  @impl true
  def handle_continue(:accept, %__MODULE__{} = state) do
    state |> dbg()

    case :gen_tcp.recv(state.socket, 0) do
      {:error, reason} ->
        {:stop, reason}

      {:ok, packet} ->
        # dbg(packet)

        case Protohacker.SpeedDaemon.Message.decode(state.remaining <> packet) do
          {:ok, message, remaining} ->
            case message do
              %Protohacker.SpeedDaemon.Message.IAmDispatcher{} = dispatcher ->
                for each_road <- dispatcher.roads do
                  DynamicSupervisor.start_child(
                    state.supervisor,
                    {Protohacker.SpeedDaemon.TicketGenerator,
                     road: each_road, dispatcher_socket: state.socket}
                  )
                end

                updated_state =
                  %{state | remaining: remaining, roads: dispatcher.roads}

                {:noreply, updated_state, {:continue, :accept}}

              %Protohacker.SpeedDaemon.Message.WantHeartbeat{} = hb ->
                start_heartbeat(state.socket, hb.interval)

                {:noreply, %{state | remaining: remaining}, {:continue, :accept}}

              other_message ->
                Logger.warning(
                  "->> TicketDispatcher receive other message: #{inspect(other_message)}"
                )

                {:noreply, %{state | remaining: remaining}, {:continue, :accept}}
            end

          error ->
            Logger.warning("->> decode message error: #{inspect(error)}")
            {:stop, error}
        end
    end
  end

  def start_heartbeat(socket, interval) do
    :timer.send_interval(interval * 100, self(), {:send_heartbeat, socket})
  end

  @impl true
  def handle_info({:send_heartbeat, socket}, state) do
    :gen_tcp.send(
      socket,
      Protohacker.SpeedDaemon.Message.Heartbeat.encode(
        %Protohacker.SpeedDaemon.Message.Heartbeat{}
      )
    )

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
