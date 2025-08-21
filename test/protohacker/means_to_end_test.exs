defmodule Protohacker.MeansToEndTest do
  use ExUnit.Case

  describe "Example Test for Means to Tend" do
    test "case 01" do
      port = Protohacker.MeansToEnd.port()
      {:ok, socket} = :gen_tcp.connect(~c"localhost", port, [:binary, active: false])

      try do
        # Insert: I 12345 101
        :gen_tcp.send(socket, <<?I, 12345::big-32, 101::big-32>>)

        # Insert: I 12346 102
        :gen_tcp.send(socket, <<?I, 12346::big-32, 102::big-32>>)

        # Insert: I 12347 100
        :gen_tcp.send(socket, <<?I, 12347::big-32, 100::big-32>>)

        # Insert: I 40960 5
        :gen_tcp.send(socket, <<?I, 40960::big-32, 5::big-32>>)

        # Query: Q 12288 16384  => should include first 3 records (12345, 12346, 12347)
        :gen_tcp.send(socket, <<?Q, 12288::big-32, 16384::big-32>>)

        # Receive exactly 4 bytes (int32 response)
        {:ok, <<mean::signed-big-32>>} = :gen_tcp.recv(socket, 4)

        # Expected mean: (101 + 102 + 100) / 3 = 303 / 3 = 101
        assert mean == 101
      after
        :gen_tcp.close(socket)
      end
    end
  end
end
