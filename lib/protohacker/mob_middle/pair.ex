defmodule Protohacker.MobMiddle.Pair do
  require Logger
  use GenServer

  @tony_account "7YWHMfk9JZe0LM0g1ZauHuiSxhI"

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary
    }
  end

  def start_link(args) do
    budget_chat_socket = Keyword.fetch!(args, :budget_chat_socket)
    client_socket = Keyword.fetch!(args, :client_socket)

    GenServer.start_link(__MODULE__, {budget_chat_socket, client_socket})
  end

  defstruct [
    :budget_chat_socket,
    :client_socket,
    :supervisor,
    :myself,
    :client_task_ref,
    :budget_chat_task_ref,
    :username
  ]

  @impl true
  def init({budget_chat_socket, client_socket}) do
    {:ok, sup} = Task.Supervisor.start_link(max_children: 2)

    state = %__MODULE__{
      budget_chat_socket: budget_chat_socket,
      client_socket: client_socket,
      supervisor: sup,
      myself: self(),
      username: nil
    }

    {:ok, state, {:continue, :accept}}
  end

  @impl true
  def handle_continue(:accept, %__MODULE__{} = state) do
    {:ok, client_task} =
      Task.Supervisor.start_child(state.supervisor, fn ->
        handle_client_connection_loop(state)
      end)

    {:ok, budget_chat_task} =
      Task.Supervisor.start_child(state.supervisor, fn ->
        handle_budget_chat_connection_loop(state)
      end)

    # Monitor the tasks so we get notified when they die
    # Process.monitor/1 sends the :DOWN message to the process that called Process.monitor
    client_ref = Process.monitor(client_task)
    budget_chat_ref = Process.monitor(budget_chat_task)

    new_state = %__MODULE__{
      state
      | client_task_ref: client_ref,
        budget_chat_task_ref: budget_chat_ref
    }

    {:noreply, new_state}
  end

  defp handle_client_connection_loop(%__MODULE__{} = state) do
    case :gen_tcp.recv(state.client_socket, 0) do
      {:ok, message} ->
        Logger.info("->> receive message from client: #{inspect(message)}")

        send(state.myself, {:from_client, message})
        handle_client_connection_loop(state)

      {:error, reason} ->
        send(state.myself, {:task_exit, :client_loop, reason})
    end
  end

  defp handle_budget_chat_connection_loop(%__MODULE__{} = state) do
    case :gen_tcp.recv(state.budget_chat_socket, 0) do
      {:ok, message} ->
        Logger.info("->> receive message from budget-chat server: #{inspect(message)}")

        send(state.myself, {:from_budget_chat, message})
        handle_budget_chat_connection_loop(state)

      {:error, reason} ->
        send(state.myself, {:task_exit, :budget_chat_loop, reason})
    end
  end

  @impl true
  def handle_info({:from_client, msg}, %__MODULE__{} = state) do
    :ok = :gen_tcp.send(state.budget_chat_socket, replace_msg(msg))
    {:noreply, state}
  end

  @impl true
  def handle_info({:from_budget_chat, msg}, %__MODULE__{} = state) do
    :ok = :gen_tcp.send(state.client_socket, replace_msg(msg))
    {:noreply, state}
  end

  @doc """
  This is triggered explicitly from the loop function on TCP error.
  """
  @impl true
  def handle_info({:task_exit, _which, reason}, %__MODULE__{} = state) do
    {:stop, {:shutdown, reason}, state}
  end

  # Task monitor down (if task crashes or exits)
  # from monitored task dies (any reason)
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    cond do
      ref == state.client_task_ref ->
        {:stop, {:client_task_died, reason}, state}

      ref == state.budget_chat_task_ref ->
        {:stop, {:budget_chat_task_died, reason}, state}

      true ->
        {:noreply, state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    # Clean up sockets
    _ = :gen_tcp.close(state.client_socket)
    _ = :gen_tcp.close(state.budget_chat_socket)
    :ok
  end

  defp replace_msg(msg) do
    # Regex to match Boguscoin addresses with proper boundaries
    regex = ~r/(?<=^| )7[A-Za-z0-9]{25,34}(?=$| )/

    Regex.replace(regex, msg, @tony_account)
  end
end
