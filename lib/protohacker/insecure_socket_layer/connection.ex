defmodule Protohacker.InsecureSocketLayer.Connection do
  use GenServer, restart: :temporary
  require Logger
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
    :ok = :inet.setopts(socket, active: :once)

    with {:ok, rest, ciphers} <- Cipher.parse_cipher_spec(data),
         false <- Cipher.no_op_ciphers?(ciphers) do
      rest |> dbg()

      {:noreply, put_in(state.ciphers, ciphers)}
    else
      error ->
        Logger.warning("there is error when client specify ciphers, error: #{inspect(error)}")
        {:stop, :norml}
    end
  end

  @impl true
  def handle_info({:tcp, socket, data}, %__MODULE__{socket: socket} = state) do
    :ok = :inet.setopts(socket, active: :once)

    # use ciphers to decode the message
    _message = Cipher.decode_message(data, state.ciphers)
    # TODO: get the most copies of topy and apply ciphers to encode the message to send

    {:noreply, state}
  end
end
