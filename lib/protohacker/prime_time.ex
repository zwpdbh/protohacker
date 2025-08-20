defmodule Protohacker.PrimeTime do
  require Logger
  use GenServer
  @port 3003
  @malformed_response ~s({"method":"isPrime","prime": "invalid"})

  def start_link([] = _opts) do
    GenServer.start_link(__MODULE__, :no_state)
  end

  defstruct [
    :listen_socket
  ]

  @impl true
  def init(:no_state) do
    listen_options = [
      mode: :binary,
      active: false,
      reuseaddr: true,
      exit_on_close: false
    ]

    case :gen_tcp.listen(@port, listen_options) do
      {:ok, listen_socket} ->
        Logger.info("->> start prime_time server at: #{inspect(@port)}")

        state = %__MODULE__{listen_socket: listen_socket}

        {:ok, state, {:continue, :accept}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:accept, %__MODULE__{} = state) do
    case :gen_tcp.accept(state.listen_socket) do
      {:ok, socket} ->
        Task.start(fn -> handle_connection(socket) end)
        {:noreply, state, {:continue, :accept}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  defp handle_connection(socket) do
    read_line_loop(socket, _buffer = "")
  end

  defp read_line_loop(socket, buffer) do
    case read_line(socket, buffer) do
      {:ok, line, rest} ->
        with {:ok, command} <- Jason.decode(line),
             {:ok, number} <- validate_request(command) do
          result = Math.prime?(number)

          Logger.info("->> #{number} is prime: #{result}")
          json_response = Jason.encode!(%{"method" => "isPrime", "prime" => result})

          :gen_tcp.send(socket, json_response <> "\n")
          read_line_loop(socket, rest)
        else
          {:error, :not_integer} ->
            json_response = Jason.encode!(%{"method" => "isPrime", "prime" => false})

            :gen_tcp.send(socket, json_response <> "\n")
            read_line_loop(socket, rest)

          {:error, :malformed} ->
            :gen_tcp.send(socket, @malformed_response)
            :gen_tcp.close(socket)

            {:error, :malformed}

          {:error, reason} ->
            :gen_tcp.send(socket, @malformed_response)
            :gen_tcp.close(socket)

            {:error, reason}
        end

        {:ok, :stop_loop}

      {:error, reason} ->
        :gen_tcp.close(socket)
        {:error, reason}
    end
  end

  defp read_line(socket, buffer) do
    case :gen_tcp.recv(socket, 0, 10_000) do
      {:ok, data} ->
        buffer = buffer <> data

        case split_line(buffer) do
          {:ok, line, rest} -> {:ok, line, rest}
          {:error, buffer} -> read_line(socket, buffer)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp split_line(buffer) do
    case String.split(buffer, ~r{\n}, parts: 2) do
      [line, rest] ->
        {:ok, line, rest}

      _ ->
        {:error, buffer}
    end
  end

  defp validate_request(%{"method" => "isPrime", "number" => n}) when is_integer(n) do
    {:ok, n}
  end

  defp validate_request(%{"method" => "isPrime", "number" => n}) when is_float(n) do
    if n == trunc(n) do
      {:ok, trunc(n)}
    else
      {:error, :not_integer}
    end
  end

  defp validate_request(_) do
    {:error, :malformed}
  end

  def port do
    @port
  end
end

defmodule Protohacker.PrimeTime.Play do
  def run_is_prime() do
    port = Protohacker.PrimeTime.port()

    {:ok, socket} =
      :gen_tcp.connect(~c"localhost", port, mode: :binary, active: false)

    :gen_tcp.send(socket, ~s({"method": "isPrime", "number": "7"}\n))

    :gen_tcp.shutdown(socket, :write)
    {:ok, response} = :gen_tcp.recv(socket, 0, 5000)

    response
    |> Jason.decode!()
  end

  def run_is_not_prime() do
    # port = Protohacker.PrimeTime.port()

    {:ok, socket} =
      :gen_tcp.connect(~c"135.237.56.239", 3002, mode: :binary, active: false)
      |> dbg()

    :gen_tcp.send(socket, ~s({"method": "isPrime", "number": "123"}) <> "\n")

    :gen_tcp.shutdown(socket, :write)
    {:ok, response} = :gen_tcp.recv(socket, 0, 5000) |> dbg()

    response
    |> Jason.decode()
    |> dbg()
  end
end
