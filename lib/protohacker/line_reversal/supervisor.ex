defmodule Protohacker.LineReversal.Supervisor do
  use Supervisor

  def start_link([] = _opts) do
    Supervisor.start_link(__MODULE__, :no_args)
  end

  @impl true
  def init(:no_args) do
    children = [
      {Registry, name: Protohacker.LineReversal.Registry, keys: :unique},
      {Protohacker.LineReversal.Acceptor, ip: {0, 0, 0, 0}, port: 5006}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
