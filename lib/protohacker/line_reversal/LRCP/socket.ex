defmodule Protohacker.LineReversal.LRCP.Socket do
  use GenServer, restart: :temporary

  alias Protohacker.LineReversal.LRCP

  @max_data_length 1_000 - String.length("/data/2147483648/2147483648//")
  @idle_timeout 60_000

  if Mix.env() == :test do
    @retransmit_interval 100
  else
    @retransmit_interval 3_000
  end

  defstruct [
    :pid
  ]

  @type t() :: %__MODULE__{pid: pid()}

  @spec start_link(list()) :: GenServer.on_start()
  def start_link([
        %LRCP.ListenSocket{} = listen_socket,
        udp_socket,
        peer_ip,
        peer_port,
        session_id
      ]) do
    name = name(listen_socket, session_id)
    GenServer.start_link(__MODULE__, {udp_socket, peer_ip, peer_port, session_id}, name: name)
  end

  defp name(%LRCP.ListenSocket{} = listen_socket, session_id) when is_integer(session_id) do
    {:via, Registry, {Protohacker.LineReversal.Registry, {listen_socket, session_id}}}
  end

  @spec send(t(), binary()) :: :ok | {:error, term()}
  def send(%__MODULE__{} = socket, data) when is_binary(data) do
    GenServer.call(socket.pid, {:send, data})
  end

  @spec controlling_process(t(), pid()) :: :ok
  def controlling_process(%__MODULE__{} = socket, pid) when is_pid(pid) do
    GenServer.call(socket.pid, {:controlling_process, pid})
  catch
    :exit, {:noproc, _} ->
      Kernel.send(pid, {:lrcp_closed, socket})
      :ok
  end

  @spec resend_connect_ack(LRCP.listen_socket(), LRCP.Protocol.session_id()) :: :ok
  def resend_connect_ack(%LRCP.ListenSocket{} = listen_socket, session_id) do
    GenServer.cast(name(listen_socket, session_id), :resend_connect_ack)
  end

  @spec handle_packet(LRCP.listen_socket(), packet) :: :ok | :not_found
        when packet:
               {:data, LRCP.Protocol.session_id(), integer(), binary()}
               | {:ack, LRCP.Protocol.session_id(), integer()}
  def handle_packet(%LRCP.ListenSocket{} = listen_socket, packet) when is_tuple(packet) do
    session_id = LRCP.Protocol.session_id(packet)

    if pid = GenServer.whereis(name(listen_socket, session_id)) do
      GenServer.cast(pid, {:handle_packet, packet})
    else
      :not_found
    end
  end

  @spec close(LRCP.listen_socket(), LRCP.Protocol.session_id()) :: :ok
  def close(%LRCP.ListenSocket{} = listen_socket, session_id) do
    GenServer.cast(name(listen_socket, session_id), :close)
  end

  # ------------------------
  # Callbacks
  # ------------------------

  defmodule State do
    defstruct [
      :udp_socket,
      :peer_ip,
      :peer_port,
      :session_id,
      :controlling_process,
      :idle_timer_ref,
      in_possition: 0,
      out_possition: 0,
      acked_out_possition: 0,
      pending_out_payload: <<>>,
      out_message_queue: :queue.new()
    ]
  end

  @impl true
  def init({udp_socket, peer_ip, peer_port, session_id}) do
    idle_timer_ref = Process.send_after(self(), :idle_timeout, @idle_timeout)

    state = %State{
      udp_socket: udp_socket,
      peer_ip: peer_ip,
      peer_port: peer_port,
      session_id: session_id,
      idle_timer_ref: idle_timer_ref
    }
  end
end
