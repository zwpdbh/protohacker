defmodule Protohacker.InsecureSocketLayer.Supervisor do
  use Supervisor

  def start_link([] = _opts) do
    Supervisor.start_link(__MODULE__, :no_args)
  end

  @impl true
  def init(:no_args) do
    children = [
      Protohacker.InsecureSocketLayer.ConnectionSupervisor,
      Protohacker.InsecureSocketLayer.Acceptor
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
