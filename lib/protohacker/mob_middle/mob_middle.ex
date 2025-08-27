defmodule Protohacker.MobMiddle do
  @moduledoc """
  https://protohackers.com/problem/5
  Write a malicious proxy server for Budget Chat.
  """
  require Logger

  use GenServer

  @port 4003

  def port do
    @port
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  defstruct [
    :listen_socket,
    :supervisor,
    :budget_chat_server,
    :budget_chat_server_port
  ]

  @impl true
  def init(opts) do
    budget_chat_server = Keyword.get(opts, :server)
    budget_chat_server_port = Keyword.get(opts, :port)

    {:ok, sup} = DynamicSupervisor.start_link(strategy: :one_for_one)

    options = [
      :binary,
      packet: :line,
      reuseaddr: true,
      active: false,
      exit_on_close: false,
      buffer: 1024 * 100
    ]

    case(:gen_tcp.listen(@port, options)) do
      {:ok, listen_socket} ->
        Logger.info("->> start mob_middle server at port: #{@port}")

        Logger.info(
          "->> budget_chat_server:port is #{budget_chat_server}:#{budget_chat_server_port}"
        )

        state = %__MODULE__{
          listen_socket: listen_socket,
          supervisor: sup,
          budget_chat_server: budget_chat_server,
          budget_chat_server_port: budget_chat_server_port
        }

        {:ok, state, {:continue, :accept}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:accept, %__MODULE__{} = state) do
    case :gen_tcp.accept(state.listen_socket) do
      {:ok, socket} ->
        handle_connection(socket, state)
        {:noreply, state, {:continue, :accept}}

      {:error, reason} ->
        :gen_tcp.close(state.listen_socket)
        {:stop, reason}
    end
  end

  # client_socket receive the message from user to proxy server.
  defp handle_connection(client_socket, %__MODULE__{} = state) do
    # 1. every message I received from client_socket, I need to send it via budget_chat_socket
    # 2. every message I received from budget_chat_socket, I need to send it to client_socket
    # 3. inspect message, find the account and replace it with @tony_account.
    # 4. do 1, and 2 in parallel
    # 5 if connection in 1 or 2 has problem, close the both connection

    {:ok, budget_chat_socket} =
      :gen_tcp.connect(
        state.budget_chat_server,
        state.budget_chat_server_port,
        mode: :binary,
        packet: :line,
        reuseaddr: true,
        active: false,
        exit_on_close: false,
        buffer: 1024 * 100
      )

    spec =
      {Protohacker.MobMiddle.Pair,
       client_socket: client_socket, budget_chat_socket: budget_chat_socket, parent: __MODULE__}

    DynamicSupervisor.start_child(state.supervisor, spec)
  end
end
