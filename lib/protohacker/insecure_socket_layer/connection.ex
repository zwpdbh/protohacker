defmodule Protohacker.InsecureSocketLayer.Connection do
  alias Protohacker.InsecureSocketLayer.MessageParser
  alias Protohacker.InsecureSocketLayer.Cipher
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
    :reverse_ciphers,
    :buffer,
    :encrypted_buffer,
    :client_pos,
    :server_pos
  ]

  @impl true
  def init(socket) do
    state = %__MODULE__{
      socket: socket,
      ciphers: [],
      reverse_ciphers: [],
      # buffer only contains processed message
      buffer: <<>>,
      encrypted_buffer: <<>>,
      client_pos: 0,
      server_pos: 0
    }

    {:ok, state}
  end

  # When there is no ciphers, the first message from client is a cipher spec
  @impl true
  def handle_info(
        {:tcp, socket, data},
        %__MODULE__{socket: socket, ciphers: []} = state
      ) do
    :ok = :inet.setopts(socket, active: :once)

    state = update_in(state.buffer, &(&1 <> data))

    with {:ok, ciphers, rest} <- Cipher.parse_cipher_spec(state.buffer),
         false <- Cipher.no_op_ciphers?(ciphers) do
      state = put_in(state.ciphers, ciphers)
      state = put_in(state.reverse_ciphers, Cipher.reverse_ciphers(ciphers))
      state = put_in(state.buffer, <<>>)
      state = put_in(state.encrypted_buffer, rest)

      handle_encrypted_data(state)
    else
      other ->
        Logger.warning(
          "there is error from first message from client, reason: #{inspect(other)}, close  the connection"
        )

        {:stop, :normal}
    end
  end

  @impl true
  def handle_info({:tcp, socket, data}, %__MODULE__{socket: socket, ciphers: ciphers} = state)
      when length(ciphers) > 0 do
    :ok = :inet.setopts(socket, active: :once)

    state = update_in(state.encrypted_buffer, &(&1 <> data))
    handle_encrypted_data(state)
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

  defp handle_encrypted_data(%__MODULE__{} = state) do
    data = Cipher.apply(state.encrypted_buffer, state.reverse_ciphers, state.client_pos)

    state = put_in(state.encrypted_buffer, <<>>)
    state = update_in(state.client_pos, &(&1 + byte_size(data)))
    state = update_in(state.buffer, &(&1 <> data))

    handle_decrypted_data(state)
  end

  defp handle_decrypted_data(%__MODULE__{} = state) do
    case String.split(state.buffer, "\n", parts: 2) do
      [line, rest] ->
        state = put_in(state.buffer, rest)
        state = handle_line(state, line)

        handle_decrypted_data(state)

      # recursively will always hit this condition
      [_buffer] ->
        {:noreply, state}
    end
  end

  defp handle_line(%__MODULE__{} = state, line) do
    case MessageParser.find_max_toy(line) do
      {:ok, max_toy} ->
        encrypted_response = Cipher.apply(max_toy <> "\n", state.ciphers, state.server_pos)

        :ok = :gen_tcp.send(state.socket, encrypted_response)
        update_in(state.server_pos, &(&1 + byte_size(encrypted_response)))

      {:error, reason} ->
        raise reason
    end
  end
end
