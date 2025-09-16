defmodule Protohacker.InsecureSocketLayer.Connection do
  use GenServer, restart: :temporary
  require Logger
  alias Protohacker.InsecureSocketLayer.MessageParser
  alias Protohacker.InsecureSocketLayer.Cipher

  def start_link(socket) do
    GenServer.start_link(__MODULE__, socket)
  end

  defstruct [
    :socket,
    :ciphers
  ]

  @impl true
  def init(socket) do
    state = %__MODULE__{socket: socket, ciphers: []}
    {:ok, state}
  end

  # When there is no ciphers, the first message from client is a cipher spec
  @impl true
  def handle_info({:tcp, socket, data}, %__MODULE__{socket: socket, ciphers: []} = state) do
    # :ok = :inet.setopts(socket, active: :once)

    data |> dbg()

    with {:ok, rest, ciphers} <- Cipher.parse_cipher_spec(data),
         false <- Cipher.no_op_ciphers?(ciphers) do
      rest |> dbg()

      {:noreply, put_in(state.ciphers, ciphers)}
    else
      error ->
        Logger.warning("there is error when client specify ciphers, error: #{inspect(error)}")
        {:stop, :normal}
    end
  end

  @impl true
  def handle_info({:tcp, socket, data}, %__MODULE__{socket: socket, ciphers: ciphers} = state)
      when length(ciphers) > 0 do
    # :ok = :inet.setopts(socket, active: :once)

    # use ciphers to decode the message
    message = Cipher.decode_message(data, state.ciphers)
    max_toy_message = MessageParser.find_max_toy(message)
    encoded_message = Cipher.encode_message(max_toy_message <> "\n", state.ciphers)

    :gen_tcp.send(state.socket, encoded_message)
    {:noreply, state}
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

  @impl true
  def terminate(reason, state) do
    dbg(reason)
    dbg(state)
    :ok
  end
end
