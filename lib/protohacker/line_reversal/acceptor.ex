defmodule Protohacker.LineReversal.Acceptor do
  require Logger
  use Task, restart: :transient

  # @port 5006

  def start_link([] = _opts) do
    Task.start_link(__MODULE__, :run, [:no_args])
  end

  def run(:no_args) do
    # TODO:
    # Q: why need ip?
    # case LRCP.listen(ip, port) do
  end
end
