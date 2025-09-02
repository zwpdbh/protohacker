defmodule Protohacker.SpeedDaemonV2.Supervisor do
  use Supervisor

  def start_link([] = _opts) do
    Supervisor.start_link(__MODULE__, :no_args)
  end

  @impl true
  def init(:no_args) do
    children = [
      {Registry, keys: :unique, name: TicketGeneratorRegistry},
      {Phoenix.PubSub, name: :speed_daemon},
      Protohacker.SpeedDaemonV2.ConnectionSupervisor,
      Protohacker.SpeedDaemonV2.Acceptor,
      Protohacker.SpeedDaemonV2.TicketGenerator
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
