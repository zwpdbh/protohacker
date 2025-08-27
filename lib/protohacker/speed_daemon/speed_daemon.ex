defmodule Protohacker.SpeedDaemon do
  @moduledoc """

  """
  require Logger

  use GenServer

  defstruct [
    :listen_socket,
    :supervisor,
    :myself
  ]

  @port 4004

  def port() do
    @port
  end

  def start_link([] = _opts) do
    GenServer.start_link(__MODULE__, :no_state)
  end

  @impl true
  def init(:no_state) do
    options = [
      mode: :binary,
      reuseaddr: true,
      exit_on_close: false,
      active: false
    ]

    case :gen_tcp.listen(@port, options) do
      {:ok, listen_socket} ->
        {:ok, _pid} = Registry.start_link(keys: :unique, name: TicketGeneratorRegistry)
        {:ok, sup} = DynamicSupervisor.start_link(strategy: :one_for_one)
        {:ok, _pid} = DynamicSupervisor.start_child(sup, {Phoenix.PubSub, name: :speed_daemon})

        Logger.info("->> start speed_daemon server at port: #{@port}")
        state = %__MODULE__{listen_socket: listen_socket, supervisor: sup, myself: self()}
        {:ok, state, {:continue, :accept}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:accept, %__MODULE__{} = state) do
    case :gen_tcp.accept(state.listen_socket) do
      {:ok, socket} ->
        Task.start(fn -> handle_connection(socket, state) end)
        {:noreply, state, {:continue, :accept}}

      {:error, reason} ->
        :gen_tcp.close(state.listen_socket)
        {:stop, reason}
    end
  end

  defp handle_connection(socket, %__MODULE__{} = state) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, message} ->
        case Protohacker.SpeedDaemon.Message.decode(message) do
          {:ok, %Protohacker.SpeedDaemon.Message.IAmCamera{} = camera, remaining} ->
            DynamicSupervisor.start_child(
              state.supervisor,
              {Protohacker.SpeedDaemon.Camera,
               camera: camera, remaining: remaining, socket: socket}
            )

          {:ok, %Protohacker.SpeedDaemon.Message.IAmDispatcher{} = dispatcher, remaining} ->
            for each_road <- dispatcher.roads do
              case DynamicSupervisor.start_child(
                     state.supervisor,
                     {Protohacker.SpeedDaemon.TicketGenerator, road: each_road}
                   ) do
                {:ok, _pid} ->
                  :ok

                {:error, {:already_started, _pid}} ->
                  :ok

                other ->
                  Logger.warning(
                    "->> could not start ticket generator for road: #{each_road}, reason: #{other}"
                  )
              end
            end

            state |> dbg()

            {:ok, _pid} =
              DynamicSupervisor.start_child(
                state.supervisor,
                {Protohacker.SpeedDaemon.TicketDispatcher,
                 dispatcher: dispatcher, remaining: remaining, socket: socket}
              )

          {:error, reason, _data} ->
            Logger.warning("->> first message received by
               #{__MODULE__} is unknown format: #{inspect(message)}, reason: #{inspect(reason)}")

            :gen_tcp.close(socket)
        end

      {:error, reason} ->
        Logger.warning("->> #{__MODULE__} handle_connection error: #{inspect(reason)}")
        :gen_tcp.close(socket)
    end
  end

  def send_heartbeat_message_loop(interval, socket) do
    message =
      %Protohacker.SpeedDaemon.Message.Heartbeat{}
      |> Protohacker.SpeedDaemon.Message.Heartbeat.encode()

    :gen_tcp.send(socket, message)
    Process.sleep(interval * 100)

    send_heartbeat_message_loop(interval, socket)
  end

  def send_error_message(socket) do
    message =
      "illegal msg"
      |> Protohacker.SpeedDaemon.Message.Error.encode()

    :gen_tcp.send(socket, message)
  end
end
