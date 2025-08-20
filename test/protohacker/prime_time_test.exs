defmodule Protohacker.PrimeTimeTest do
  use ExUnit.Case

  @port Protohacker.PrimeTime.port()

  describe "test isPrime" do
    test "case01 -- is prime" do
      {:ok, socket} =
        :gen_tcp.connect(~c"localhost", @port, mode: :binary, active: false)

      assert :gen_tcp.send(socket, ~s({"method": "isPrime", "number": "123"}\n))

      :gen_tcp.shutdown(socket, :write)
      assert :gen_tcp.recv(socket, 0, 5000) == {:ok, ~s({"method":"isPrime","prime":false})}
    end
  end
end
