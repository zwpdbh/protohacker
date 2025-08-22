defmodule Protohacker.PrimeTime do
  require Logger
  use GenServer
  @port 3003
  @malformed_response ~s({"prime": false})

  def start_link([] = _opts) do
    GenServer.start_link(__MODULE__, :no_state)
  end

  defstruct [
    :listen_socket,
    :supervisor
  ]

  @impl true
  def init(:no_state) do
    {:ok, sup} = Task.Supervisor.start_link(max_children: 100)

    listen_options = [
      mode: :binary,
      active: false,
      reuseaddr: true,
      exit_on_close: false,
      packet: :line,
      buffer: 1024 * 100
    ]

    case :gen_tcp.listen(@port, listen_options) do
      {:ok, listen_socket} ->
        # :inet.getopts(listen_socket, [:buffer]) |> dbg()

        Logger.info("->> start prime_time server at: #{inspect(@port)}")
        state = %__MODULE__{listen_socket: listen_socket, supervisor: sup}

        {:ok, state, {:continue, :accept}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:accept, %__MODULE__{} = state) do
    case :gen_tcp.accept(state.listen_socket) do
      {:ok, socket} ->
        Task.Supervisor.start_child(state.supervisor, fn -> handle_connection_loop(socket) end)
        {:noreply, state, {:continue, :accept}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  defp handle_connection_loop(socket) do
    with {:ok, each_line} <- :gen_tcp.recv(socket, 0, 10_000),
         {:ok, command} <- Jason.decode(each_line),
         {:ok, number} <- validate_request(command) do
      result = Math.prime?(number)

      Logger.info("->> #{number} is prime: #{result}")
      json_response = Jason.encode!(%{"method" => "isPrime", "prime" => result})

      :gen_tcp.send(socket, json_response <> "\n")
      handle_connection_loop(socket)
    else
      {:error, :not_integer} ->
        json_response = Jason.encode!(%{"method" => "isPrime", "prime" => false})

        :gen_tcp.send(socket, json_response <> "\n")
        handle_connection_loop(socket)

      {:error, :malformed} ->
        :gen_tcp.send(socket, @malformed_response <> "\n")
        :gen_tcp.close(socket)

        {:error, :malformed}

      {:error, reason} ->
        Logger.info("->> error, reason: #{inspect(reason)}")

        :gen_tcp.send(socket, @malformed_response <> "\n")
        :gen_tcp.close(socket)

        {:error, reason}
    end
  end

  def validate_request(%{"method" => "isPrime", "number" => n}) when is_integer(n) do
    {:ok, n}
  end

  def validate_request(%{"method" => "isPrime", "number" => n}) when is_float(n) do
    if n == trunc(n) do
      {:ok, trunc(n)}
    else
      {:error, :not_integer}
    end
  end

  def validate_request(unknown) do
    Logger.info("->> validate_request unknown: #{inspect(unknown)}")
    {:error, :malformed}
  end

  def port do
    @port
  end
end

defmodule Protohacker.PrimeTime.Play do
  def run_is_prime() do
    {:ok, socket} =
      :gen_tcp.connect(~c"135.237.56.239", 3002, mode: :binary, active: false)

    :gen_tcp.send(socket, ~s({"method": "isPrime", "number": -7.0}\n))

    :gen_tcp.shutdown(socket, :write)
    {:ok, response} = :gen_tcp.recv(socket, 0, 5000)

    response
    |> Jason.decode!()
  end

  def run_is_not_prime() do
    # port = Protohacker.PrimeTime.port()

    {:ok, socket} =
      :gen_tcp.connect(~c"135.237.56.239", 3002, mode: :binary, active: false)

    :gen_tcp.send(socket, ~s({"method": "isPrime", "number": "123"}) <> "\n")

    :gen_tcp.shutdown(socket, :write)
    {:ok, response} = :gen_tcp.recv(socket, 0, 5000)

    response
    |> Jason.decode()
  end

  def run_example_01() do
    input =
      "{\"number\":53473226,\"method\":\"isPrime\"}\n{\"number\":85285537,\"method\":\"isPrime\"}\n{\"number\":67157929,\"method\":\"isPrime\"}\n{\"method\":\"isPrime\",\"number\":96329491}\n{\"method\":\"isPrime\",\"number\":42457156}\n{\"number\":64124109,\"method\":\"isPrime\"}\n{\"method\":\"isPrime\",\"number\":1515031}\n{\"number\":61215697,\"method\":\"isPrime\"}\n{\"number\":13872304,\"method\":\"isPrime\"}\n{\"method\":\"isPrime\",\"number\":52233862}\n{\"number\":2951832,\"method\":\"isPrime\"}\n{\"method\":\"isPrime\",\"number\":82248559}\n{\"number\":98826439,\"method\":\"isPrime\"}\n{\"method\":\"isPrime\",\"number\":90663977}\n{\"number\":37330619,\"method\":\"isPrime\"}\n{\"number\":7745642,\"method\":\"isPrime\"}\n{\"number\":66787807,\"method\":\"isPrime\"}\n"

    {:ok, socket} =
      :gen_tcp.connect(~c"localhost", Protohacker.PrimeTime.port(),
        mode: :binary,
        active: false,
        packet: :line
      )

    :gen_tcp.send(socket, input)

    :gen_tcp.shutdown(socket, :write)

    recv_loop(socket)
  end

  defp recv_loop(socket) do
    case :gen_tcp.recv(socket, 0, 5000) do
      {:ok, response} ->
        response |> Jason.decode()
        response |> dbg()

        recv_loop(socket)

      {:error, :closed} ->
        {:ok, :stopped}
    end
  end
end
