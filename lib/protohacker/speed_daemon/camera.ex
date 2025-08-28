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
    state =
      %__MODULE__{
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
                if hb.interval > 0 do
                  # Start heartbeat
                  Protohacker.SpeedDaemon.HeartbeatManager.start_heartbeat(
                    hb.interval,
                    state.socket
                  )
                else
                  # Cancel heartbeat
                  Protohacker.SpeedDaemon.HeartbeatManager.cancel_heartbeat(state.socket)
                end

                {:noreply, %{state | remaining: remaining}, {:continue, :accept}}

              %Protohacker.SpeedDaemon.Message.Plate{} = plate ->
                plate |> dbg()

                :ok =
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
end
