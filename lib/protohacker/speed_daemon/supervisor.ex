defmodule Protohacker.SpeedDaemon.Supervisor do
  use Supervisor

  def start_link([] = _opts) do
    Supervisor.start_link(__MODULE__, :no_args)
  end

  @impl true
  def init(:no_args) do
    registry_opts = [
      name: Protohacker.SpeedDaemon.DispatchersRegistry,
      keys: :duplicate,
      listeners: [Protohacker.SpeedDaemon.TicketManager]
    ]

    children = [
      {Registry, registry_opts},
      {Protohacker.SpeedDaemon.TicketManager, []},
      {Protohacker.SpeedDaemon.ConnectionSupervisor, []},
      {Protohacker.SpeedDaemon.Acceptor, []}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
