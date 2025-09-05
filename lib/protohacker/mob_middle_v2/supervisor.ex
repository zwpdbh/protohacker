defmodule Protohacker.MobMiddleV2.Supervisor do
  use Supervisor

  def start_link([] = _opts) do
    Supervisor.start_link(__MODULE__, :no_args)
  end

  @impl true
  def init(:no_args) do
    children = [
      # ConnectionSupervisor accept a socket from accept and start a Connection per connection.
      # ConnectionSupervisor is a DynamicSupervisor
      Protohacker.MobMiddleV2.ConnectionSupervisor,
      # Acceptor is the Module which listen the address and accept connection.
      # Then, it use ConnectionSupervisor to spawn a Connection.
      # It is a supervised Task.
      Protohacker.MobMiddleV2.Acceptor
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
