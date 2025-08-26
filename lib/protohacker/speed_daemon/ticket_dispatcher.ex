defmodule Protohacker.SpeedDaemon.TicketDispatcher do
  use GenServer

  require Logger
  alias Protohacker.SpeedDaemon.Message.IAmDispatcher

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
    :socket
  ]

  def start_link(opts) do
    %IAmDispatcher{} = dispatcher = Keyword.fetch!(opts, :dispatcher)
    remaining = Keyword.fetch!(opts, :remaining)
    socket = Keyword.fetch!(opts, :socket)

    GenServer.start_link(__MODULE__, {dispatcher, remaining, socket})
  end

  @impl true
  def init({%IAmDispatcher{} = dispatcher, remaining, socket}) do
    state = %__MODULE__{
      roads: dispatcher.roads,
      myself: self(),
      remaining: remaining,
      socket: socket
    }

    {:ok, state, {:continue, :accept}}
  end

  @impl true
  def handle_continue(:accept, %__MODULE__{} = state) do
    for each_road <- state.roads do
      :ok = Phoenix.PubSub.subscribe(:speed_daemon, "ticket_dispatcher_road_#{each_road}")
    end

    with {:ok, packet} <- :gen_tcp.recv(state.socket, 0),
         {:ok, message, remaining} <-
           Protohacker.SpeedDaemon.Message.decode(state.remaining <> packet),
         :ok <- handle_message(message, state) do
      updated_state = %__MODULE__{state | remaining: remaining}
      {:noreply, updated_state, {:continue, :accept}}
    else
      {:error, reason, data} ->
        Logger.debug("#{__MODULE__} decode unknow format data: #{inspect(data)}")
        Protohacker.SpeedDaemon.send_error_message(state.socket)
        {:stop, reason}

      {:error, reason} ->
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

      other_message ->
        {:error, "->> ticket dispatcher, it received: #{other_message}"}
    end
  end

  @impl true
  def terminate(_reason, %__MODULE__{} = state) do
    :gen_tcp.close(state.socket)
    :ok
  end
end
