defmodule Protohacker.MeansToEnd do
  @moduledoc """
  https://protohackers.com/problem/2
  """
  require Logger

  use GenServer

  @port 3005

  def port do
    @port
  end

  def start_link([] = _opts) do
    GenServer.start_link(__MODULE__, :no_state)
  end

  defstruct [
    :listen_socket
  ]

  @impl true
  def init(:no_state) do
    case :gen_tcp.listen(@port,
           mode: :binary,
           active: false,
           reuseaddr: true,
           exit_on_close: false
         ) do
      {:ok, listen_socket} ->
        Logger.info("->> start means_to_end server at port: #{@port}")
        {:ok, %__MODULE__{listen_socket: listen_socket}, {:continue, :accept}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:accept, %__MODULE__{} = state) do
    case :gen_tcp.accept(state.listen_socket) do
      {:error, reason} ->
        {:stop, reason}

      {:ok, socket} ->
        Task.start_link(fn -> handle_connection_loop(socket, _db = :gb_trees.empty()) end)
        {:noreply, state, {:continue, :accept}}
    end
  end

  defp handle_connection_loop(socket, records) do
    case :gen_tcp.recv(socket, 9) do
      {:ok, packet} ->
        case process_packet_to_command(packet) do
          {:query, timestamp_start, timestamp_end} ->
            :send_back
            mean = compute_mean_from_records(records, {timestamp_start, timestamp_end})

            case :gen_tcp.send(socket, <<mean::32>>) do
              :ok ->
                handle_connection_loop(socket, records)

              {:error, reason} ->
                Logger.error("->> #{__MODULE__} :gen_tcp.send error: #{inspect(reason)}")
            end

          {:insert, timestamp, new_record} ->
            updated_records = :gb_trees.insert(timestamp, new_record, records)
            handle_connection_loop(socket, updated_records)
        end

      {:error, reason} ->
        Logger.info("->> #{__MODULE__} :gen_tcp.recv error: #{inspect(reason)} ")
        {:error, reason}
    end
  end

  # Each message from a client is 9 bytes long
  defp process_packet_to_command(<<?I, timestamp::signed-32, price::signed-32>>) do
    {:insert, timestamp, price}
  end

  defp process_packet_to_command(<<?Q, timestamp_start::signed-32, timestamp_end::signed-32>>) do
    {:query, timestamp_start, timestamp_end}
  end

  defp compute_mean_from_records(records, {timestamp_start, timestamp_end}) do
    # If interval is invalid
    if timestamp_start > timestamp_end do
      0
    else
      # Use iterator to traverse only the keys in [timestamp_start, timestamp_end]
      iterator = :gb_trees.iterator_from(timestamp_start, records)
      values = collect_values_in_range(iterator, timestamp_end)

      case values do
        [] ->
          0

        prices ->
          sum = Enum.sum(prices)
          count = length(prices)
          # integer division
          div(sum, count)
      end
    end
  end

  # Helper: collect all values from iterator where key <= max_time
  defp collect_values_in_range(iterator, max_time, acc \\ [])

  defp collect_values_in_range(iterator, max_time, acc) do
    case :gb_trees.next(iterator) do
      {key, value, next_iterator} when key <= max_time ->
        collect_values_in_range(next_iterator, max_time, [value | acc])

      _ ->
        # Done: either no more entries or key > max_time
        acc
    end
  end
end
