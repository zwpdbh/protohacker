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

  @type t() :: %__MODULE__{pid: pid()}

  defstruct [
    :pid
  ]

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
      in_position: 0,
      out_position: 0,
      acked_out_position: 0,
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

    udp_send(state, "/ack/#{state.session_id}/0/")

    {:ok, state}
  end

  @impl true
  def handle_info(message, state)

  def handle_info(:idle_timeout, %State{} = state) do
    {:stop, :normal, state}
  end

  def handle_info(:retransmit_pending_data, %State{} = state) do
    state = update_in(state.out_position, fn p -> p - byte_size(state.pending_out_payload) end)

    {:noreply, send_data(state, state.pending_out_payload)}
  end

  @impl true
  def handle_call({:send, data}, _from, %State{} = state) do
    state = update_in(state.pending_out_payload, fn payload -> payload <> data end)
    state = send_data(state, data)

    {:reply, :ok, state}
  end

  def handle_call({:controlling_process, pid}, _from, %State{} = state) do
    state = put_in(state.controlling_process, pid)

    # REVIEW: get_and_update_in
    {messages, state} =
      get_and_update_in(state.out_message_queue, fn queue ->
        {:queue.to_list(queue), :queue.new()}
      end)

    Enum.each(messages, &Kernel.send(pid, &1))

    {:reply, :ok, state}
  end

  @impl true
  def handle_cast(cast, state)

  def handle_cast(:close, %State{} = state) do
    {:stop, :normal, state}
  end

  def handle_cast(:resend_connect_ack, %State{} = state) do
    udp_send(state, "/ack/#{state.session_id}/#{state.in_position}")

    {:noreply, state}
  end

  def handle_cast({:handle_packet, {:data, _session_id, position, data}}, %State{} = state) do
    state = reset_idle_timer(state)

    if position == state.in_position do
      unescaped_data = unescape_data(data)

      state =
        update_in(state.in_position, fn in_position -> in_position + byte_size(unescaped_data) end)

      udp_send(state, "/ack/#{state.session_id}/#{state.in_position}/")

      state =
        send_or_queue_message(state, {:lrcp, %__MODULE__{pid: self()}, unescaped_data})

      {:noreply, state}
    else
      udp_send(state, "/ack/#{state.session_id}/#{state.in_position}/")
      {:noreply, state}
    end
  end

  def handle_cast({:handle_packet, {:ack, _session_id, length}}, %State{} = state) do
    cond do
      length <= state.acked_out_position ->
        {:noreply, state}

      length > state.out_position ->
        udp_send(state, "/close/#{state.session_id}/")

        state =
          send_or_queue_message(
            state,
            {:lrcp_error, %__MODULE__{pid: self()}, :client_misbehaving}
          )

        {:stop, :normal, state}

      length < state.acked_out_position + byte_size(state.pending_out_payload) ->
        transmitted_bytes = length - state.acked_out_position

        still_pending_payload =
          :binary.part(
            state.pending_out_payload,
            transmitted_bytes,
            byte_size(state.pending_out_payload) - transmitted_bytes
          )

        udp_send(
          state,
          "/data/#{state.session_id}/#{state.acked_out_position + transmitted_bytes}/" <>
            escape_data(still_pending_payload) <> "/"
        )

        state = put_in(state.acked_out_position, length)
        state = put_in(state.pending_out_payload, still_pending_payload)
        {:noreply, state}

      length == state.out_position ->
        state = put_in(state.acked_out_position, length)
        state = put_in(state.pending_out_payload, <<>>)

        {:noreply, state}

      true ->
        raise """
        Should never reach this.

        state: #{inspect(state)}
        length: #{length}
        """
    end
  end

  defp send_data(%State{} = state, <<>>) do
    Process.send_after(self(), :retransmit_pending_data, @retransmit_interval)
    state
  end

  defp send_data(%State{} = state, data) do
    {chunk, rest} =
      case data do
        <<chunk::binary-size(@max_data_length), rest::binary>> -> {chunk, rest}
        chunk -> {chunk, ""}
      end

    {chunk, rest}

    udp_send(state, "/data/#{state.session_id}/#{state.out_position}/#{escape_data(chunk)}/")
    state = update_in(state.out_position, fn x -> x + byte_size(chunk) end)
    send_data(state, rest)
  end

  defp escape_data(data) do
    data
    |> String.replace("\\", "\\\\")
    |> String.replace("/", "\\/")
  end

  defp unescape_data(data) do
    data
    |> String.replace("\\/", "/")
    |> String.replace("\\\\", "\\")
  end

  defp udp_send(%State{} = state, data) do
    :ok = :gen_udp.send(state.udp_socket, state.peer_ip, state.peer_port, data)
  end

  defp reset_idle_timer(%State{} = state) do
    Process.cancel_timer(state.idle_timer_ref)
    idle_timer_ref = Process.send_after(self(), :idle_timeout, @idle_timeout)
    put_in(state.idle_timer_ref, idle_timer_ref)
  end

  defp send_or_queue_message(%State{} = state, message) do
    if state.controlling_process do
      Kernel.send(state.controlling_process, message)
      state
    else
      update_in(state.out_message_queue, fn q -> :queue.in(message, q) end)
    end
  end
end
