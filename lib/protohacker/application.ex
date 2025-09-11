defmodule Protohacker.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Fetch config at startup
    server = Application.get_env(:protohacker, :budget_chat_server, ~c"chat.protohackers.com")
    port = Application.get_env(:protohacker, :budget_chat_server_port, 16963)

    children = [
      # Starts a worker by calling: Protohacker.Worker.start_link(arg)
      # {Protohacker.Worker, arg}
      Protohacker.EchoServer,
      Protohacker.PrimeTime,
      Protohacker.MeansToEnd,
      Protohacker.BudgetChat,
      Protohacker.UnusualDatabase,
      {Protohacker.MobMiddle, [server: server, port: port]},
      # Protohacker.MobMiddleV2.Supervisor,
      # Protohacker.SpeedDaemon
      Protohacker.SpeedDaemon.Supervisor,
      Protohacker.LineReversal.Supervisor
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Protohacker.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
