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
        spec = {Protohacker.BudgetChat.UserConnection, socket: socket, parent: __MODULE__}

        DynamicSupervisor.start_child(
          state.user_supervisor,
          spec
        )

        {:noreply, state, {:continue, :accept}}
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
  require Logger
  use GenServer

  defstruct [
    :socket,
    :parent,
    :name,
    :myself
  ]

  def start_link(args) do
    socket = Keyword.fetch!(args, :socket)
    parent = Keyword.fetch!(args, :parent)

    state = %__MODULE__{
      socket: socket,
      parent: parent,
      name: nil,
      myself: nil
    }

    GenServer.start_link(__MODULE__, state)
  end

  @impl true
  def init(%__MODULE__{} = state) do
    {:ok, %__MODULE__{state | myself: self()}, {:continue, :register}}
  end

  @impl true
  def handle_continue(:register, state) do
    # Send initial message
    if is_nil(state.name) do
      send_message(state.socket, "Welcome to budgetchat! What shall I call you?")
    end

    Task.start_link(fn -> handle_connection_loop(state) end)
    {:noreply, state}
  end

  defp handle_connection_loop(%__MODULE__{} = state) do
    case :gen_tcp.recv(state.socket, 0) do
      {:ok, message} ->
        send(state.myself, {:ok, message |> String.trim_trailing()})
        handle_connection_loop(state)

      {:error, reason} ->
        send(state.myself, {:error, reason})
    end
  end

  # When the name is nil, the first message from a client set the user's name
  @impl true
  def handle_info({:ok, message}, %__MODULE__{name: nil} = state) do
    with {:ok, name} <- check_user_name_valid?(message),
         {:ok, name, other_users} <- Protohacker.BudgetChat.register_user(name, state.myself) do
      # if new user name is registered, broadcast to other users
      Protohacker.BudgetChat.broadcast_message(
        "* #{name} has entered the room",
        name,
        state.myself
      )

      # notify current user about the other users
      existing_users_message =
        ("* The room contains: " <> Enum.join(other_users, " ,")) |> String.trim()

      Logger.info("->> let user know who are in the chat exclude himself")
      send_message(state.socket, existing_users_message)

      {:noreply, %{state | name: name}}
    else
      {:error, :name_is_not_allowed} ->
        send_message(state.socket, "username is not allowed")
        :gen_tcp.close(state.socket)
        {:noreply, state}

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
  def handle_info({:ok, message}, %__MODULE__{name: name} = state) do
    Protohacker.BudgetChat.broadcast_message("[#{name}] #{message}", name, state.myself)
    {:noreply, state}
  end

  @impl true
  def handle_info({:error, reason}, %__MODULE__{} = state) do
    reason |> dbg()

    unless state.name |> is_nil do
      :ok = Protohacker.BudgetChat.unregister_user(state.name, state.myself)

      Protohacker.BudgetChat.broadcast_message(
        "* #{state.name} has left the room",
        state.name,
        state.myself
      )
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("->> unhandled msg: #{msg}, for #{__MODULE__}, state: #{inspect(state)}")
    {:noreploy, state}
  end

  defp send_message(socket, text) do
    json = Jason.encode!(%{text: text})
    :gen_tcp.send(socket, json <> "\n")
  end

  # which must contain at least 1 character, and must consist entirely of alphanumeric characters (uppercase, lowercase, and digits).
  defp check_user_name_valid?(name) when is_binary(name) do
    if String.length(name) >= 1 and String.match?(name, ~r/^[a-zA-Z0-9]+$/) do
      {:ok, name}
    else
      {:error, :name_is_not_allowed}
    end
  end
end
