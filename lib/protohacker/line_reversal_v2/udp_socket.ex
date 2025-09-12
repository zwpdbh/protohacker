defmodule Protohacker.LineReversalV2.UdpSocket do
  require Logger
  alias Protohacker.LineReversal.LRCP
  use GenServer

  @port 5007

  def start_link([] = _opts) do
    GenServer.start_link(__MODULE__, :no_args, name: __MODULE__)
  end

  defstruct [
    :socket
  ]

  @impl true
  def init(:no_args) do
    options = [
      mode: :binary,
      active: :once,
      recbuf: 1000
    ]

    case :gen_udp.open(@port, options) do
      {:ok, socket} ->
        Logger.debug("start line reversal server at port: #{@port}")
        {:ok, %__MODULE__{socket: socket}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_info({:udp, udp_socket, ip, port, packet}, state) do
    :ok = :inet.setopts(udp_socket, active: :once)

    case LRCP.Protocol.parse_packet(packet) do
      {:ok, packet} ->
        handle_packet(state, ip, port, packet)

      :error ->
        {:noreply, state}
    end
  end

  defp handle_packet(%__MODULE__{} = state, ip, port, packet) do
    session_id = LRCP.Protocol.session_id(packet)

    case Protohacker.LineReversalV2.ConnectionSupervisor.start_child(ip, port, session_id) do
      {:ok, client_pid} ->
        GenServer.cast(client_pid, {:process_packet, packet})
        {:noreply, state}

      {:error, {:already_started, client_pid}} ->
        GenServer.cast(client_pid, {:resent_connect_ack, packet})
        {:noreply, state}

      {:error, reason} ->
        Logger.error(
          "failed to create client for ip: #{inspect(ip)}}, port: #{inspect(port)}, session_id: #{inspect(session_id)}"
        )

        {:stop, reason}
    end
  end
end
