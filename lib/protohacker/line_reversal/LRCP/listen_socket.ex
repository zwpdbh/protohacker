defmodule Protohacker.LineReversal.LRCP.ListenSocket do
  use GenServer
  require Logger
  alias Protohacker.LineReversal.LRCP

  @type t() :: %__MODULE__{pid: pid()}

  defstruct [
    :pid
  ]

  def start_link(options) when is_list(options) do
    with {:ok, pid} <- GenServer.start_link(__MODULE__, options) do
      {:ok, %__MODULE__{pid: pid}}
    end
  end

  # So, after using start_link to get a running ListenSocket, we call accept on it.
  # who call this accept? The process do accept_loop on listen_socket.
  # LRCP.ListenSocket call an instance of itself for what?
  # It wait response from GenServer.call for :accept.
  def accept(%__MODULE__{pid: pid} = _listen_socket) do
    GenServer.call(pid, :accept, _timeout = :infinity)
  end

  # ------------------------
  # Callbacks
  # ------------------------

  # Why use two queues?
  # It is the classic producer-consumer pattern.
  # Using queues is one of the most fundamental, widely used, and battle-tested patterns
  # in asynchronous, event-driven, and concurrent systems.
  # Notice the async, event nature when we set "active: :once" in init of this GenServer to
  # open UDP connection.
  # So, a connection packet could arrive any time.
  # The first arrival of udp packet and call LRCP.accept is not determined.
  defmodule State do
    defstruct [
      :udp_socket,
      :supervisor,
      # A queue of processes waiting to accept a new connection
      # Enqueue is done by LRCP.accept(listen_socket)
      # Dequeue is done when a client sends /connect/session_id/
      accept_queue: :queue.new(),
      # A queue of already-created LRCP.Sockets (sessions) that are waiting to be accepted.
      # Enqueued when a /connect/../ packet arrives, and a LRCP.Socket is spawned, but no one is currently waiting in accept_queue.
      # In other words, the socket is pre-created and waiting to be picked up by the next LRCP.accept() call.
      # Dequeued when some one calls LRCP.accept() and there is socket waiting.
      ready_sockets: :queue.new()
    ]
  end

  @impl true
  def init(options) do
    ip = Keyword.fetch!(options, :ip)
    port = Keyword.fetch!(options, :port)

    udp_options = [
      :binary,
      active: :once,
      recbuf: 10_000,
      ip: ip
    ]

    with {:ok, udp_socket} <- :gen_udp.open(port, udp_options),
         {:ok, supervisor} <- DynamicSupervisor.start_link(max_children: 200) do
      {:ok, %State{udp_socket: udp_socket, supervisor: supervisor}}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:accept, from, %__MODULE__.State{} = state) do
    case get_and_update_in(state.ready_sockets, fn q -> :queue.out(q) end) do
      {{:value, %LRCP.Socket{} = socket}, state} ->
        {:reply, {:ok, socket}, state}

      {:empty, state} ->
        updated_state =
          update_in(state.accept_queue, fn q ->
            from |> dbg()
            :queue.in(from, q)
          end)

        {:noreply, updated_state}
    end
  end

  @impl true
  def handle_info({:udp, udp_socket, ip, port, packet}, %State{udp_socket: udp_socket} = state) do
    :ok = :inet.setopts(udp_socket, active: :once)

    case LRCP.Protocol.parse_packet(packet) do
      {:ok, packet} ->
        handle_packet(state, ip, port, packet)

      :error ->
        {:noreply, state}
    end
  end

  # ------------------------
  # Helpers
  # ------------------------
  defp handle_packet(%State{} = state, ip, port, {:connect, session_id}) do
    spec = {LRCP.Socket, [%__MODULE__{pid: self()}, state.udp_socket, ip, port, session_id]}

    case DynamicSupervisor.start_child(state.supervisor, spec) do
      {:ok, socket_pid} ->
        socket = %LRCP.Socket{pid: socket_pid}

        case get_and_update_in(state.accept_queue, fn q -> :queue.out(q) end) do
          {{:value, from}, state} ->
            # REVIEW the usage of GenServer.reply
            GenServer.reply(from, {:ok, socket})
            {:noreply, state}

          {:empty, state} ->
            state =
              update_in(state.ready_sockets, fn q ->
                socket |> dbg()

                :queue.in(socket, q)
              end)

            {:noreply, state}
        end

      {:error, {:already_started, _pid}} ->
        :ok = LRCP.Socket.resend_connect_ack(%__MODULE__{pid: self()}, session_id)
        {:noreply, state}

      {:error, reason} ->
        Logger.error("failed to start connection: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  defp handle_packet(state, ip, port, {:close, session_id}) do
    _ = LRCP.Socket.close(%__MODULE__{pid: self()}, session_id)
    send_close(state, ip, port, session_id)

    {:noreply, state}
  end

  defp handle_packet(state, ip, port, packet) do
    case LRCP.Socket.handle_packet(%__MODULE__{pid: self()}, packet) do
      :ok -> :ok
      :not_found -> send_close(state, ip, port, LRCP.Protocol.session_id(packet))
    end

    {:noreply, state}
  end

  defp send_close(state, ip, port, session_id) do
    :ok = :gen_udp.send(state.udp_socket, ip, port, "/close/#{session_id}/")
  end
end
