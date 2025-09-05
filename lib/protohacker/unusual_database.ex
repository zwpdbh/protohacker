defmodule Protohacker.UnusualDatabase do
  require Logger
  use GenServer

  @port 3009

  def start_link([] = _opts) do
    GenServer.start_link(__MODULE__, :no_state)
  end

  def port do
    @port
  end

  defstruct store: %{},
            socket: nil

  @impl true
  def init(:no_state) do
    Logger.debug(" start unusual-database server at port: #{@port}")

    options = [
      mode: :binary,
      active: false,
      recbuf: 1000
    ]

    case :gen_udp.open(@port, options) do
      {:ok, socket} ->
        state =
          %__MODULE__{socket: socket}

        {:ok, put_in(state.store["version"], "1.0"), {:continue, :recv}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:recv, %__MODULE__{} = state) do
    case :gen_udp.recv(state.socket, 0) do
      {:ok, {address, port, packet}} ->
        Logger.debug(
          "received UDP pakcet from #{inspect(address)}:#{inspect(port)}: #{inspect(packet)}"
        )

        state =
          case String.split(packet, "=", parts: 2) do
            ["version", _] ->
              Logger.debug(" ignore update version from client")
              state

            [key, value] ->
              Logger.debug(" insert key: #{inspect(key)}, value: #{inspect(value)}")

              put_in(state.store[key], value)

            [key] ->
              Logger.debug(" requested key: #{inspect(key)}")
              packet = "#{key}=#{state.store[key]}"

              :gen_udp.send(state.socket, address, port, packet)
              state
          end

        {:noreply, state, {:continue, :recv}}

      {:error, reason} ->
        {:stop, reason, state}
    end
  end
end
