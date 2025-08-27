defmodule Protohacker.SpeedDaemon.Camera do
  @moduledoc """

  """
  require Logger

  use GenServer

  defstruct [
    :socket,
    :remaining,
    :road,
    :mile,
    :limit
  ]

  def child_spec(opts) do
    %{
      id: __MODULE__,
      restart: :temporary,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(opts) do
    socket = Keyword.fetch!(opts, :socket)
    GenServer.start_link(__MODULE__, socket)
  end

  @impl true
  def init(socket) do
    state = %__MODULE__{
      socket: socket
    }

    :gen_tcp.controlling_process(socket, self())
    {:ok, %{state | remaining: <<>>}, {:continue, :accept}}
  end

  @impl true
  def handle_continue(:accept, %__MODULE__{} = state) do
    case :gen_tcp.recv(state.socket, 0) do
      {:error, reason} ->
        {:stop, reason}

      {:ok, packet} ->
        case Protohacker.SpeedDaemon.Message.decode(state.remaining <> packet) do
          {:ok, message, remaining} ->
            case message do
              %Protohacker.SpeedDaemon.Message.IAmCamera{} = camera ->
                updated_state = %{
                  state
                  | remaining: remaining,
                    road: camera.road,
                    mile: camera.mile,
                    limit: camera.limit
                }

                {:noreply, updated_state, {:continue, :accept}}

              %Protohacker.SpeedDaemon.Message.WantHeartbeat{} = hb ->
                start_heartbeat(state.socket, hb.interval)

                {:noreply, %{state | remaining: remaining}, {:continue, :accept}}

              %Protohacker.SpeedDaemon.Message.Plate{} = plate ->
                Phoenix.PubSub.broadcast!(
                  :speed_daemon,
                  "camera_road_#{state.road}",
                  %{
                    plate: plate.plate,
                    timestamp: plate.timestamp,
                    road: state.road,
                    mile: state.mile,
                    limit: state.limit
                  }
                )

                {:noreply, %{state | remaining: remaining}, {:continue, :accept}}

              other_message ->
                Logger.warning(
                  "->> Camera socket receive other message: #{inspect(other_message)}"
                )

                {:noreply, %{state | remaining: remaining}, {:continue, :accept}}
            end

          error ->
            {:stop, error}
        end
    end
  end

  @impl true
  def terminate(_reason, %__MODULE__{} = state) do
    :gen_tcp.close(state.socket)
    :ok
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
end
