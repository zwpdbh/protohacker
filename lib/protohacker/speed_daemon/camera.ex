defmodule Protohacker.SpeedDaemon.Camera do
  @moduledoc """

  """
  require Logger

  use GenServer

  alias Protohacker.SpeedDaemon.Camera
  alias Phoenix.PubSub

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

  def start_link([opts]) do
    %Protohacker.SpeedDaemon.Message.IAmCamera{} = camera = Keyword.fetch!(opts, :camera)
    socket = Keyword.fetch!(opts, :socket)
    remaining = Keyword.fetch!(opts, :remaining)

    GenServer.start_link(__MODULE__, {camera, remaining, socket})
  end

  @impl true
  def init({%Protohacker.SpeedDaemon.Message.IAmCamera{} = camera, remaining, socket}) do
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
    with {:ok, packet} <- :gen_tcp.recv(state.socket, 0),
         {:ok, message, remaining} <-
           Protohacker.SpeedDaemon.Message.decode(state.remaining <> packet),
         :ok <- handle_message(message, state) do
      updated_state = %__MODULE__{state | remaining: remaining}
      {:noreply, updated_state, {:continue, :accept}}
    else
      {:error, reason} ->
        {:stop, reason}

      {:error, reason, data} ->
        Logger.debug(
          "->> decode message failed from #{__MODULE__}, reason: #{inspect(reason)}, data: #{inspect(data)}"
        )

        Protohacker.SpeedDaemon.send_error_message(state.socket)

        {:stop, reason}
    end
  end

  defp handle_message(message, %__MODULE__{} = state) do
    Logger.debug("->> received message: #{message}")

    case message do
      %Protohacker.SpeedDaemon.Message.WantHeartbeat{interval: interval} ->
        Task.async(fn ->
          Protohacker.SpeedDaemon.send_heartbeat_message_loop(interval, state.socket)
        end)

        :ok

      %Protohacker.SpeedDaemon.Message.Plate{plate: plate, timestamp: timestamp} ->
        Phoenix.PubSub.broadcast(:speed_daemon, "camera_road_#{state.road}", %{
          plate: plate,
          timestamp: timestamp,
          limit: state.limit,
          mile: state.mile
        })

        :ok

      other_message ->
        {:error, "->> as Camera, it received other message: #{other_message}"}
    end
  end

  @impl true
  def terminate(_reason, %__MODULE__{} = state) do
    :gen_tcp.close(state.socket)
    :ok
  end
end
