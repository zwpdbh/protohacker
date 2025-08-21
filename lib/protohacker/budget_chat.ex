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
    GenServer.start_link(__MODULE__, :no_state)
  end

  @impl true
  def init(:no_state) do
    options = [
      reuseaddr: true,
      active: false,
      packet: :line
    ]

    with {:ok, listen_socket} <- :gen_tcp.listen(@port, options),
         {:ok, sup} <- DynamicSupervisor.start_link(strategy: :one_for_one) do
      Logger.info("->> start budget_chat server at port: #{@port}")

      state = %__MODULE__{
        listen_socket: listen_socket,
        users: %{},
        user_supervisor: sup
      }

      {:ok, state, {:continue, :accept}}
    else
      {:error, reason} ->
        Logger.error("#{__MODULE__} init failed: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:accept, %__MODULE__{} = state) do
    case :gen_tcp.accept(state.listen_socket) do
      {:error, reason} ->
        Logger.error("->> #{__MODULE__} failed to accept, error: #{inspect(reason)}")
        {:stop, reason}

      {:ok, socket} ->
        case DynamicSupervisor.start_child(
               state.user_supervisor,
               {Protohacker.BudgetChat.UserConnection, socket: socket, parent: __MODULE__}
             ) do
          {:ok, _pid} ->
            {:noreply, state, {:continue, :accept}}

          {:error, reason} ->
            Logger.warning(
              "->> failed to start user connection with supervisor, error: #{inspect(reason)}"
            )

            :gen_tcp.close(socket)
            {:noreply, state, {:continue, :accept}}
        end
    end
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
  def handle_cast({message, _name, pid}, %__MODULE__{} = state) do
    for {_, other_user_pid} <- state.users, other_user_pid != pid do
      send(other_user_pid, message)
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
    GenServer.cast(__MODULE__, {ensure_newline(message), from_name, from_pid})
  end

  defp ensure_newline(message) when is_binary(message) do
    if String.ends_with?(message, "\n") do
      message
    else
      message <> "\n"
    end
  end
end

defmodule Protohacker.BudgetChat.UserConnection do
  use GenServer

  def start_link(args) do
    socket = Keyword.fetch!(args, :socket)
    parent = Keyword.fetch!(args, :parent)

    GenServer.start_link(__MODULE__, %{socket: socket, parent: parent, name: nil})
  end

  defstruct [
    :socket,
    :parent,
    :name
  ]

  @impl true
  def init(%__MODULE__{} = state) do
    # Set process to trap exits so we can clean up
    Process.flag(:trap_exit, true)
    # Enable active once mode
    :ok = :gen_tcp.controlling_process(state.socket, self())
    enable_active_once(state.socket)

    {:ok, state, {:continue, :register}}
  end

  @impl true
  def handle_continue(:register, state) do
    # Send initial message
    if is_nil(state.name) do
      send_message(state.socket, "Welcome to budgetchat! What shall I call you?")
    end

    {:noreply, state}
  end

  # When the name is nil, the first message from a client set the user's name
  @impl true
  def handle_info({:tcp, _socket, name}, %__MODULE__{name: nil} = state) do
    # Re-enable active once
    enable_active_once(state.socket)

    with true <- check_user_name_valid?(name),
         {:ok, name, other_users} <- Protohacker.BudgetChat.register_user(name, self()) do
      # if new user name is registered, broadcast to other users
      Protohacker.BudgetChat.broadcast_message("* #{name} has entered the room", name, self())

      # notify current user about the other users
      existing_users_message =
        "* The room contains: " <> Enum.join(other_users, " ,")

      send_message(state.socket, existing_users_message)

      {:noreply, %{state | name: name}}
    else
      {:error, :duplicated_name} ->
        send_message(state.socket, "username is duplicated")
        :gen_tcp.close(state.socket)
        {:noreply, state}
    end
  end

  @doc """
  when receive message from user, boardcast it
  """
  @impl true
  def handle_info({:tcp, _socket, data}, %__MODULE__{name: name} = state) do
    # Re-enable active once
    enable_active_once(state.socket)
    Protohacker.BudgetChat.broadcast_message("[#{name}] #{data}", name, self())
    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp_closed, _socket}, %__MODULE__{} = state) do
    :ok = Protohacker.BudgetChat.unregister_user(state.name, self())

    Protohacker.BudgetChat.broadcast_message(
      "* #{state.name} has left the room",
      state.name,
      self()
    )

    {:stop, :normal, state}
  end

  defp enable_active_once(socket) do
    :inet.setopts(socket, active: :once)
  end

  defp send_message(socket, text) do
    json = Jason.encode!(%{text: text})
    :gen_tcp.send(socket, json <> "\n")
  end

  # which must contain at least 1 character, and must consist entirely of alphanumeric characters (uppercase, lowercase, and digits).
  defp check_user_name_valid?(name) when is_binary(name) do
    String.length(name) > 0 and String.match?(name, ~r/^[a-zA-Z0-9]+$/)
  end

  defp check_user_name_valid?(_), do: false
end
