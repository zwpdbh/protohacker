defmodule Protohacker.BudgetChat.UserConnection do
  require Logger
  use GenServer

  defstruct [
    :socket,
    :parent,
    :name,
    :myself,
    :supervisor
  ]

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      # ← Critical: don't restart after client disconnects
      restart: :temporary
    }
  end

  def start_link(args) do
    socket = Keyword.fetch!(args, :socket)
    parent = Keyword.fetch!(args, :parent)

    state = %__MODULE__{
      socket: socket,
      parent: parent,
      name: nil,
      myself: nil,
      supervisor: nil
    }

    GenServer.start_link(__MODULE__, state)
  end

  @impl true
  def init(%__MODULE__{} = state) do
    {:ok, sup} = Task.Supervisor.start_link(max_children: 1)

    {:ok, %__MODULE__{state | myself: self(), supervisor: sup}, {:continue, :register}}
  end

  @impl true
  def handle_continue(:register, %__MODULE__{} = state) do
    # Send initial message
    if is_nil(state.name) do
      send_message(state.socket, "Welcome to budgetchat! What shall I call you?")
    end

    Task.Supervisor.start_child(state.supervisor, fn -> handle_connection_loop(state) end)

    {:noreply, state}
  end

  defp handle_connection_loop(%__MODULE__{} = state) do
    case :gen_tcp.recv(state.socket, 0) do
      {:ok, message} ->
        send(state.myself, {:loop_recv, message |> String.trim_trailing()})
        handle_connection_loop(state)

      {:error, reason} ->
        send(state.myself, {:loop_error, reason})
    end
  end

  # When the name is nil, the first message from a client set the user's name
  @impl true
  def handle_info({:loop_recv, message}, %__MODULE__{name: nil} = state) do
    with {:ok, name} <- check_user_name_valid?(message),
         {:ok, name, other_users} <-
           Protohacker.BudgetChat.register_user(name, state.myself) do
      # if new user name is registered, broadcast to other users
      Protohacker.BudgetChat.broadcast_message(
        "* #{name} has entered the room",
        name,
        state.myself
      )

      # notify current user about the presence of other users
      existing_users_message =
        ("* The room contains: " <> Enum.join(other_users, ", ")) |> String.trim()

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
  def handle_info({:loop_recv, message}, %__MODULE__{} = state) do
    Protohacker.BudgetChat.broadcast_message(
      "[#{state.name}] #{message}",
      state.name,
      state.myself
    )

    {:noreply, state}
  end

  @impl true
  def handle_info({:from_broadcast, message}, %__MODULE__{} = state) do
    send_message(state.socket, message)
    {:noreply, state}
  end

  @impl true
  def handle_info({:loop_error, reason}, %__MODULE__{} = state) do
    unless is_nil(state.name) do
      :ok = Protohacker.BudgetChat.unregister_user(state.name, state.myself)

      Protohacker.BudgetChat.broadcast_message(
        "* #{state.name} has left the room",
        state.name,
        state.myself
      )
    end

    case reason do
      :closed ->
        {:stop, :normal, state}

      _ ->
        Logger.debug("->> loop recv error: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning(
      "->> unhandled msg: #{inspect(msg)}, for #{__MODULE__}, state: #{inspect(state)}"
    )

    {:noreploy, state}
  end

  defp send_message(socket, text) do
    :gen_tcp.send(socket, Protohacker.BudgetChat.Common.ensure_newline(text))
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
