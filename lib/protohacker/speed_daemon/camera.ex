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
           Protohacker.SpeedDaemon.Message.decode(state.remaining <> packet) do
      Logger.debug("->> receive message: #{inspect(message)}")

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

  @impl true
  def terminate(_reason, %__MODULE__{} = state) do
    :gen_tcp.close(state.socket)
    :ok
  end
end
