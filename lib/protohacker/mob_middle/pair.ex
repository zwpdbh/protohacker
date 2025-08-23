defmodule Protohacker.MobMiddle.Pair do
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
    client_socket = Keyword.fetch(args, :client_socket)

    GenServer.start_link(__MODULE__, {budget_chat_socket, client_socket})
  end

  defstruct [:budget_chat_socket, :client_socket, :supervisor]

  @impl true
  def init({budget_chat_socket, client_socket}) do
    {:ok, sup} = Task.Supervisor.start_link(max_children: 2)

    state = %__MODULE__{
      budget_chat_socket: budget_chat_socket,
      client_socket: client_socket,
      supervisor: sup
    }

    {:ok, state, {:continue, :accept}}
  end

  @impl true
  def handle_continue(:accept, %__MODULE__{} = state) do
    Task.Supervisor.start_child(state.supervisor, fn ->
      handle_client_connection_loop(state.client_socket)
    end)

    Task.Supervisor.start_child(state.supervisor, fn ->
      handle_budget_chat_connection_loop(state.budget_chat_socket)
    end)

    {:noreply, state}
  end

  defp handle_client_connection_loop(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, _message} ->
        handle_client_connection_loop(socket)
    end
  end

  defp handle_budget_chat_connection_loop(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, _message} ->
        handle_client_connection_loop(socket)
    end
  end

  def handle_info(msg, state) do
  end
end
