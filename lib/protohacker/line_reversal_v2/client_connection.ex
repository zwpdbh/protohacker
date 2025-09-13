defmodule Protohacker.LineReversalV2.ClientConnection do
  require Logger
  use GenServer

  @idle_timeout 60_000

  def start_link(opts) do
    ip = Keyword.fetch!(opts, :ip)
    port = Keyword.fetch!(opts, :port)
    session_id = Keyword.fetch!(opts, :session_id)

    GenServer.start_link(__MODULE__, {ip, port, session_id}, name: name(ip, port, session_id))
  end

  defstruct [
    :ip,
    :port,
    :session_id,
    :idle_timer_ref,
    in_position: 0,
    out_position: 0,
    acked_out_position: 0,
    pending_out_payload: <<>>
    # out_message_queue: :queue.new()
  ]

  @impl true
  def init({ip, port, session_id}) do
    idle_timer_ref = Process.send_after(self(), :idle_timeout, @idle_timeout)
    {:ok, %__MODULE__{ip: ip, port: port, session_id: session_id, idle_timer_ref: idle_timer_ref}}
  end

  defp name(ip, port, session_id) do
    {:via, Registry, {Protohacker.LineReversalV2.Registry, {ip, port, session_id}}}
  end

  @impl true
  def handle_cast(:connect, %__MODULE__{} = state) do
    udp_send(state, "/ack/#{state.session_id}/0/")
    {:noreply, state}
  end

  @impl true
  def handle_cast(:resent_connect_ack, %__MODULE__{} = state) do
    udp_send(state, "/ack/#{state.session_id}/#{state.in_position}")

    {:noreply, state}
  end

  @impl true
  def handle_cast(:close, %__MODULE__{} = state) do
    {:stop, :normal, state}
  end

  @impl true
  def handle_cast({:process_binary, pos, binary_data}, %__MODULE__{} = state) do
    state = reset_idle_timer(state)

    if pos == state.in_position do
      unescaped_data = unescape_data(binary_data)

      state =
        update_in(state.in_position, fn in_position -> in_position + byte_size(unescaped_data) end)

      udp_send(state, "/ack/#{state.session_id}/#{state.in_position}/")
      udp_send(state, unescaped_data)

      {:noreply, state}
    else
      udp_send(state, "/ack/#{state.session_id}/#{state.in_position}/")
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:ack, pos}, %__MODULE__{} = state) do
    cond do
      pos <= state.acked_out_position ->
        {:noreply, state}

      pos > state.out_position ->
        udp_send(state, "/close/#{state.session_id}")
        Logger.warning("#{inspect(state)} indicate client misbehaving")
        {:stop, :normal, state}

      pos < state.acked_out_position + byte_size(state.pending_out_payload) ->
        transmitted_bytes = pos - state.acked_out_position

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

        state = put_in(state.acked_out_position, pos)
        state = put_in(state.pending_out_payload, still_pending_payload)
        {:noreply, state}

      pos == state.out_position ->
        state = put_in(state.acked_out_position, pos)
        state = put_in(state.pending_out_payload, <<>>)

        {:noreply, state}

      true ->
        raise """
        Should never reach this.

        state: #{inspect(state)}
        pos: #{pos}
        """
    end
  end

  @impl true
  def terminate(_reason, %__MODULE__{ip: ip, port: port, session_id: session_id}) do
    Registry.delete_meta(Protohacker.LineReversalV2.Registry, {ip, port, session_id})
    :ok
  end

  defp udp_send(%__MODULE__{ip: ip, port: port} = _state, data) do
    Protohacker.LineReversalV2.UdpSocket.upd_send(ip, port, data)
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

  defp reset_idle_timer(%__MODULE__{} = state) do
    Process.cancel_timer(state.idle_timer_ref)
    idle_timer_ref = Process.send_after(self(), :idle_timeout, @idle_timeout)
    put_in(state.idle_timer_ref, idle_timer_ref)
  end
end
