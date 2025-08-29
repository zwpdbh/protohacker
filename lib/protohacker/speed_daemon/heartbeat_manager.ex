defmodule Protohacker.SpeedDaemon.HeartbeatManager do
  use GenServer

  def start_link([] = _opts) do
    GenServer.start_link(__MODULE__, :no_state, name: __MODULE__)
  end

  defstruct [
    :records,
    :supervisor
  ]

  @impl true
  def init(:no_state) do
    {:ok, sup} = Task.Supervisor.start_link(max_children: 100)

    {:ok, %__MODULE__{records: %{}, supervisor: sup}}
  end

  @impl true
  def handle_call(
        {:start_heartbeat, interval, socket},
        _from,
        %__MODULE__{} = state
      ) do
    # Cancel any existing heartbeat for this socket first
    case Map.get(state.records, socket) do
      nil ->
        # Start a new task
        {:ok, task_pid} =
          Task.Supervisor.start_child(state.supervisor, fn -> do_heartbeat(interval, socket) end)

        # Update the records
        updated_records = Map.put(state.records, socket, task_pid)
        updated_state = %{state | records: updated_records}

        {:reply, {:ok, task_pid}, updated_state}

      task_pid ->
        # Task.Supervisor.terminate_child/2 is the correct way to stop a task
        {:reply, {:error, task_pid}, state}
    end
  end

  @impl true
  def handle_call({:cancel_heartbeat, socket}, _from, %__MODULE__{} = state) do
    # Look up the task for this socket
    case Map.get(state.records, socket) do
      nil ->
        # No heartbeat task running for this socket, nothing to do
        :ok

      task_pid ->
        # Stop the task using the supervisor
        Task.Supervisor.terminate_child(state.supervisor, task_pid)
    end

    # Remove the socket from the records
    updated_records = Map.delete(state.records, socket)
    updated_state = %{state | records: updated_records}

    {:reply, :ok, updated_state}
  end

  defp do_heartbeat(interval, socket) do
    :gen_tcp.send(
      socket,
      Protohacker.SpeedDaemon.Message.Heartbeat.encode(
        %Protohacker.SpeedDaemon.Message.Heartbeat{}
      )
    )

    :timer.sleep(interval * 100)
    do_heartbeat(interval, socket)
  end

  def start_heartbeat(interval, socket) do
    GenServer.call(__MODULE__, {:start_heartbeat, interval, socket})
  end

  def cancel_heartbeat(socket) do
    GenServer.call(__MODULE__, {:cancel_heartbeat, socket})
  end
end
