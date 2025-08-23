defmodule Protohacker.MobMiddle do
  @moduledoc """
  https://protohackers.com/problem/5
  Write a malicious proxy server for Budget Chat.
  """
  alias ElixirLS.LanguageServer.Dialyzer.Supervisor

  use GenServer

  @tony_account "7YWHMfk9JZe0LM0g1ZauHuiSxhI"
  @budget_chat_server ~c"chat.protohackers.com"
  @budget_chat_server_port 16963

  @port 4001

  def start_link([] = _opts) do
    GenServer.start_link(__MODULE__, :no_state)
  end

  defstruct [
    :listen_socket,
    :supervisor
  ]

  @impl true
  def init(:no_state) do
    {:ok, sup} = Task.Supervisor.start_link(max_children: 100)

    options = [
      :binary,
      packet: :line,
      resudeaddr: true,
      active: false,
      exit_on_close: false,
      buffer: 1024 * 100
    ]

    case(:gen_tcp.listen(@port, options)) do
      {:ok, listen_socket} ->
        state = %__MODULE__{listen_socket: listen_socket, supervisor: sup}

        {:ok, state, {:continue, :accept}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:accept, %__MODULE__{} = state) do
    case :gen_tcp.accept(state.listen_socket) do
      {:ok, socket} ->
        Task.Supervisor.start_child(state.supervisor, fn ->
          handle_connection(socket)
        end)

        {:noreply, state, {:continue, :accept}}

      {:error, reason} ->
        :gen_tcp.close(state.listen_socket)
        {:stop, reason}
    end
  end

  defp handle_connection(client_socket) do
    # 1. every message I received from client_socket, I need to send it via budget_chat_socket
    # 2. every message I received from budget_chat_socket, I need to send it to client_socket
    # 3. inspect message, find the account and replace it with @tony_account.
    # 4. do 1, and 2 in parallel
    # 5 if connection in 1 or 2 has problem, close the both connection

    {:ok, budget_chat_socket} =
      :gen_tcp.connect(@budget_chat_server, @budget_chat_server_port,
        mode: :binary,
        active: false
      )
  end
end
