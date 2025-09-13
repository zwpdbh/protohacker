defmodule Protohacker.LineReversalV2.UdpSocket do
  require Logger

  alias Protohacker.LineReversal.LRCP
  use GenServer

  @port 5007

  def start_link([] = _opts) do
    GenServer.start_link(__MODULE__, :no_args, name: __MODULE__)
  end

  defstruct [
    :socket,
    :pending_packets
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
        {:ok, %__MODULE__{socket: socket, pending_packets: []}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_info({:udp, udp_socket, ip, port, packet}, %__MODULE__{} = state) do
    :ok = :inet.setopts(udp_socket, active: :once)

    state =
      update_in(state.pending_packets, fn packets ->
        packets ++ [{ip, port, packet}]
      end)

    {:noreply, state, {:continue, :process_packet}}
  end

  # @impl true
  # def handle_continue(
  #       :process_packet,
  #       %__MODULE__{pending_packets: packets} = state
  #     ) do
  #   packets |> dbg()

  #   {:noreply, state}
  # end

  @impl true
  def handle_continue(
        :process_packet,
        %__MODULE__{pending_packets: packets} = state
      ) do
    packets |> dbg()

    case packets do
      [] ->
        {:noreply, state}

      [{ip, port, packet} | rest] ->
        case LRCP.Protocol.parse_packet(packet) do
          {:ok, message} ->
            case handle_message(state, ip, port, message) do
              {:ok, state} ->
                state = put_in(state.pending_packets, rest)
                {:noreply, state}

              {:error, reason} ->
                {:stop, reason}
            end

          :error ->
            state = put_in(state.pending_packets, rest)
            {:noreply, state}
        end
    end
  end

  # ------------------------
  # callbacks
  # ------------------------

  @impl true
  def handle_cast({:udp_send, ip, port, data}, state) do
    :gen_udp.send(state.socket, ip, port, data)

    {:noreply, state}
  end

  # ------------------------
  # helpers
  # ------------------------
  defp handle_message(%__MODULE__{} = state, ip, port, {:connect, session_id}) do
    case Protohacker.LineReversalV2.ConnectionSupervisor.start_child(ip, port, session_id) do
      {:ok, client_pid} ->
        GenServer.cast(client_pid, :connect)
        {:ok, state}

      {:error, {:already_started, client_pid}} ->
        GenServer.cast(client_pid, :resent_connect_ack)
        {:ok, state}

      {:error, reason} ->
        Logger.error(
          "failed to create client for ip: #{inspect(ip)}}, port: #{inspect(port)}, session_id: #{inspect(session_id)}"
        )

        {:error, reason}
    end
  end

  defp handle_message(%__MODULE__{} = state, ip, port, {:close, session_id}) do
    with {:ok, client_pid} <- find_client_connection(ip, port, session_id) do
      GenServer.cast(client_pid, :close)

      {:ok, state}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_message(%__MODULE__{} = state, ip, port, {:data, session_id, pos, binary_data}) do
    with {:ok, client_pid} <- find_client_connection(ip, port, session_id) do
      GenServer.cast(client_pid, {:process_binary, pos, binary_data})
      {:ok, state}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_message(%__MODULE__{} = state, ip, port, {:ack, session_id, pos}) do
    with {:ok, client_pid} <- find_client_connection(ip, port, session_id) do
      GenServer.cast(client_pid, {:ack, pos})
      {:ok, state}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp find_client_connection(ip, port, session_id) do
    case Registry.lookup(Protohacker.LineReversalV2.Registry, {ip, port, session_id}) do
      [] ->
        {:error,
         "there is no associated client connection for #{inspect({ip, port, session_id})}"}

      [{pid, _value}] ->
        {:ok, pid}
    end
  end

  # ------------------------
  # Interface function
  # ------------------------
  def upd_send(ip, port, data) do
    GenServer.cast(__MODULE__, {:udp_send, ip, port, data})
  end

  @impl true
  def terminate(reason, _state) do
    Logger.warning("terminating: #{inspect(reason)}")
    :ok
  end
end
