defmodule Protohacker.EchoServerTest do
  use ExUnit.Case

  test "echo anything back" do
    port = Protohacker.EchoServer.port()

    {:ok, socket} =
      :gen_tcp.connect(~c"localhost", port, mode: :binary, active: false)

    assert :gen_tcp.send(socket, "foo") == :ok
    assert :gen_tcp.send(socket, "bar") == :ok
    :gen_tcp.shutdown(socket, :write)

    assert :gen_tcp.recv(socket, 0, 5000) == {:ok, "foobar"}
  end
end
