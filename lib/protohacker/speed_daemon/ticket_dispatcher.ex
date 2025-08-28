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
    :socket
  ]

  def start_link(opts) do
    socket = Keyword.fetch!(opts, :socket)
    dispatcher = Keyword.fetch!(opts, :dispatcher)
    remaining = Keyword.fetch!(opts, :remaining)
    GenServer.start_link(__MODULE__, {socket, dispatcher, remaining})
  end

  @impl true
  def init({socket, %Protohacker.SpeedDaemon.Message.IAmDispatcher{} = dispatcher, remaining}) do
    state =
      %__MODULE__{
        socket: socket,
        remaining: remaining,
        roads: dispatcher.roads
      }

    # |> dbg(charlists: :as_lists)

    {:ok, state, {:continue, :accept}}
  end

  @impl true
  def handle_continue(:accept, %__MODULE__{} = state) do
    case :gen_tcp.recv(state.socket, 0) |> dbg() do
      {:error, reason} ->
        {:stop, reason}

      {:ok, packet} ->
        case Protohacker.SpeedDaemon.Message.decode((state.remaining <> packet) |> dbg()) do
          {:ok, message, remaining} ->
            case message do
              %Protohacker.SpeedDaemon.Message.WantHeartbeat{} = hb ->
                start_heartbeat(hb.interval)

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

  def start_heartbeat(interval) do
    # because the value of interval is 0.1 second unit. So, value 25 means 2.5 seconds
    :timer.send_interval(interval * 100, self(), :send_heartbeat)
  end

  @impl true
  def handle_info(:send_heartbeat, %__MODULE__{} = state) do
    :gen_tcp.send(
      state.socket,
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
