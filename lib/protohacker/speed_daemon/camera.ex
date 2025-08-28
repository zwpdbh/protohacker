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
    camera = Keyword.fetch!(opts, :camera)
    remaining = Keyword.fetch!(opts, :remaining)

    GenServer.start_link(__MODULE__, {socket, camera, remaining})
  end

  @impl true
  def init({socket, %Protohacker.SpeedDaemon.Message.IAmCamera{} = camera, remaining})
      when is_binary(remaining) do
    state = %__MODULE__{
      socket: socket,
      remaining: remaining,
      road: camera.road,
      mile: camera.mile,
      limit: camera.limit
    }

    {:ok, state, {:continue, :accept}}
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
            Logger.warning("->> decode message error: #{inspect(error)}")
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
    # because the value of interval is 0.1 second unit. So, value 25 means 2.5 seconds
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
