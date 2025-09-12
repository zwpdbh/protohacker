defmodule Protohacker.LineReversalV2.Supervisor do
  use Supervisor

  def start_link([] = _opts) do
    Supervisor.start_link(__MODULE__, :no_args)
  end

  # For TCP
  # 1. Acceptor -- Task
  # We have do listen -> {:ok, listen_socket}
  # :gen_tcp.accept(listen_socket) -> {:ok, socket}
  # 2. Connection -- Per socket -- Per client
  # The received data is a stream.

  # For UDP
  # All we have is one socket <- :gen_udp.open(@port, options)
  # We need to maintain our virtual client by ourself
  # The received data is a self contained datagram.

  @impl true
  def init(:no_args) do
    children = [
      {Registry, name: Protohacker.LineReversalV2.Registry, keys: :unique},
      {Protohacker.LineReversalV2.ConnectionSupervisor, []},
      {Protohacker.LineReversalV2.UdpSocket, []}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
