defmodule Protohacker.SpeedDaemon do
  @moduledoc """

  """
  require Logger

  use GenServer

  defstruct [
    :listen_socket,
    :myself,
    :supervisor,
    :task_supervisor
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

    with {:ok, listen_socket} <- :gen_tcp.listen(@port, options),
         {:ok, _pid} <- Registry.start_link(keys: :unique, name: TicketGeneratorRegistry),
         {:ok, sup} <- DynamicSupervisor.start_link(strategy: :one_for_one),
         {:ok, task_sup} <- Task.Supervisor.start_link(max_children: 100),
         {:ok, _pid} <- DynamicSupervisor.start_child(sup, {Phoenix.PubSub, name: :speed_daemon}) do
      Logger.info("->> start speed_daemon server at port: #{@port}")

      state = %__MODULE__{
        listen_socket: listen_socket,
        supervisor: sup,
        task_supervisor: task_sup,
        myself: self()
      }

      {:ok, state, {:continue, :accept}}
    else
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:accept, %__MODULE__{} = state) do
    case :gen_tcp.accept(state.listen_socket) do
      {:ok, socket} ->
        Task.Supervisor.start_child(state.task_supervisor, fn ->
          handle_connection(socket, state)
        end)

        {:noreply, state, {:continue, :accept}}

      {:error, reason} ->
        :gen_tcp.close(state.listen_socket)
        {:stop, reason}
    end
  end

  defp switch_on_peek(socket) do
    :inet.setopts(socket, [{:recv, :peek}])
  end

  defp switch_off_peek(socket) do
    :inet.setopts(socket, [{:recv, :normal}])
  end

  defp handle_connection(socket, %__MODULE__{} = state) do
    switch_on_peek(socket)

    case :gen_tcp.recv(socket, 1, 0) do
      {:ok, message} ->
        case message do
          <<0x80>> ->
            switch_off_peek(socket)

            {:ok, _pid} =
              DynamicSupervisor.start_child(
                state.supervisor,
                {Protohacker.SpeedDaemon.Camera, socket: socket}
              )

          <<0x81>> ->
            switch_off_peek(socket)

            {:ok, _pid} =
              DynamicSupervisor.start_child(
                state.supervisor,
                {Protohacker.SpeedDaemon.TicketDispatcher,
                 socket: socket, supervisor: state.supervisor}
              )
        end

      {:error, reason} ->
        Logger.warning("->> #{__MODULE__} handle_connection error: #{inspect(reason)}")
        :gen_tcp.close(socket)
    end
  end

  def send_error_message(socket) do
    message =
      "illegal msg"
      |> Protohacker.SpeedDaemon.Message.Error.encode()

    :gen_tcp.send(socket, message)
  end

  # def start_heartbeat(socket, interval) do
  #   :timer.send_interval(interval * 100, self(), {:send_heartbeat, socket})
  # end

  # def handle_info({:send_heartbeat, socket}, state) do
  #   :gen_tcp.send(socket, Protohacker.SpeedDaemon.Message.Heartbeat.encode(%{}))
  #   {:noreply, state}
  # end

  # def send_heartbeat_message_loop(interval, socket) do
  #   message =
  #     %Protohacker.SpeedDaemon.Message.Heartbeat{}
  #     |> Protohacker.SpeedDaemon.Message.Heartbeat.encode()

  #   :gen_tcp.send(socket, message)
  #   Process.sleep(interval * 100)

  #   send_heartbeat_message_loop(interval, socket)
  # end
end
