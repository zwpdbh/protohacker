defmodule Protohacker.LineReversal.ConnectionSupervisor do
  use DynamicSupervisor
  alias Protohacker.LineReversal.LRCP

  def start_link([] = _opts) do
    DynamicSupervisor.start_link(__MODULE__, :no_args, name: __MODULE__)
  end

  @impl true
  def init(:no_args) do
    DynamicSupervisor.init(strategy: :one_for_one, max_children: 100)
  end

  def start_child(socket) do
    child_spec = {Protohacker.LineReversal.Connection, socket}

    # TODO: use the conn and socket do controlling_process?...
    with {:ok, conn} <- DynamicSupervisor.start_child(__MODULE__, child_spec),
         :ok <- LRCP.controlling_process(socket, conn) do
      {:ok, conn}
    end
  end
end
