defmodule Protohacker.InsecureSocketLayer.Connection do
  use GenServer, restart: :temporary
  require Logger
  # alias Protohacker.InsecureSocketLayer.MessageParser
  # alias Protohacker.InsecureSocketLayer.Cipher

  def start_link(socket) do
    GenServer.start_link(__MODULE__, socket)
  end

  defstruct [
    :socket,
    :ciphers,
    :buffer
  ]

  @impl true
  def init(socket) do
    state = %__MODULE__{socket: socket, ciphers: [], buffer: <<>>}

    {:ok, state}
  end

  # When there is no ciphers, the first message from client is a cipher spec
  @impl true
  def handle_info(
        {:tcp, socket, _data},
        %__MODULE__{socket: socket, ciphers: []} = _state
      ) do
    :ok = :inet.setopts(socket, active: :once)

    :todo |> dbg()
  end

  @impl true
  def handle_info({:tcp, socket, _data}, %__MODULE__{socket: socket, ciphers: ciphers} = _state)
      when length(ciphers) > 0 do
    :ok = :inet.setopts(socket, active: :once)

    :todo |> dbg()
  end

  @impl true
  def handle_info({:tcp_error, socket, reason}, %__MODULE__{socket: socket} = state) do
    Logger.error("Connection closed because of error: #{inspect(reason)}")
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:tcp_closed, socket}, %__MODULE__{socket: socket} = state) do
    Logger.debug("Connection closed by client")
    {:stop, :normal, state}
  end
end
