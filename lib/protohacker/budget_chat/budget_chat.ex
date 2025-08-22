defmodule Protohacker.BudgetChat do
  @moduledoc """
  https://protohackers.com/problem/3
  """
  require Logger

  use GenServer

  @port 3007

  def port do
    @port
  end

  defstruct [
    :listen_socket,
    # users is a map in which the key is user's name, and the value is the corresponding connection's pid
    :users,
    :user_supervisor
  ]

  def start_link([] = _opts) do
    GenServer.start_link(__MODULE__, :no_state, name: __MODULE__)
  end

  @impl true
  def init(:no_state) do
    options = [
      reuseaddr: true,
      active: false,
      packet: :line,
      exit_on_close: false,
      buffer: 1024 * 100,
      mode: :binary
    ]

    with {:ok, listen_socket} <- :gen_tcp.listen(@port, options),
         {:ok, sup} <- DynamicSupervisor.start_link(strategy: :one_for_one) do
      Logger.info("->> start budget_chat server at port: #{@port}")

      state = %__MODULE__{
        listen_socket: listen_socket,
        users: %{},
        user_supervisor: sup
      }

      Task.start_link(fn ->
        accept_loop(state)
        send(Protohacker.BudgetChat, {:accept_loop_stopped, self()})
      end)

      {:ok, state}
    else
      {:error, reason} ->
        Logger.error("#{__MODULE__} init failed: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  defp accept_loop(%__MODULE__{} = state) do
    case :gen_tcp.accept(state.listen_socket) do
      {:ok, socket} ->
        spec = {Protohacker.BudgetChat.UserConnection, socket: socket, parent: __MODULE__}
        DynamicSupervisor.start_child(state.user_supervisor, spec)

      {:error, reason} ->
        Logger.error("Accept error: #{inspect(reason)}")
        # Don't crash; maybe terminate if it's a fatal error
        if reason not in [:closed, :einval], do: :timer.sleep(100), else: exit(:shutdown)
    end

    # Loop back — accept next connection
    accept_loop(state)
  end

  @impl true
  def handle_info({:accept_loop_stopped, _from}, state) do
    Logger.warning("accept loop stopped")

    {:stop, :accept_loop_stopped, state}
  end

  @impl true
  def terminate(_reason, %__MODULE__{listen_socket: listen_socket} = _state) do
    Logger.info("Shutting down BudgetChat server and closing listen socket")

    if listen_socket do
      :gen_tcp.close(listen_socket)
    end

    :ok
  end

  @impl true
  def handle_call({:register_user, name, pid}, _from, %__MODULE__{} = state) do
    if Map.has_key?(state.users, name) do
      {:reply, {:error, :duplicated_name}, state}
    else
      other_users = Map.keys(state.users)
      users = Map.put(state.users, name, pid)

      {:reply, {:ok, name, other_users}, %{state | users: users}}
    end
  end

  @impl true
  def handle_call({:unregister_user, name, _pid}, _from, %__MODULE__{} = state) do
    updated_users = state.users |> Map.filter(fn {user_name, _pid} -> name != user_name end)

    {:reply, :ok, %{state | users: updated_users}}
  end

  @impl true
  def handle_cast({:broadcast, message, _name, pid}, %__MODULE__{} = state) do
    for {_, other_user_pid} <- state.users, other_user_pid != pid do
      send(other_user_pid, {:from_broadcast, message})
    end

    {:noreply, state}
  end

  def register_user(name, pid) when is_binary(name) and is_pid(pid) do
    GenServer.call(__MODULE__, {:register_user, name, pid})
  end

  def unregister_user(name, pid) when is_binary(name) and is_pid(pid) do
    GenServer.call(__MODULE__, {:unregister_user, name, pid})
  end

  def broadcast_message(message, from_name, from_pid)
      when is_binary(from_name) and is_binary(message) and is_pid(from_pid) do
    # detect if the message is end with new line, otherwise, add it.
    GenServer.cast(__MODULE__, {:broadcast, ensure_newline(message), from_name, from_pid})
  end

  defp ensure_newline(message) when is_binary(message) do
    if String.ends_with?(message, "\n") do
      message
    else
      message <> "\n"
    end
  end
end
