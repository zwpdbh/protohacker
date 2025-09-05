defmodule Protohacker.MobMiddleV2.ConnectionSupervisor do
  use DynamicSupervisor

  def start_link([] = _opts) do
    DynamicSupervisor.start_link(__MODULE__, :no_args, name: __MODULE__)
  end

  @impl true
  def init(:no_args) do
    DynamicSupervisor.init(strategy: :one_for_one, max_children: 50)
  end

  def start_child(socket) do
    child_spec = {Protohacker.MobMiddleV2.Connection, socket}

    with {:ok, conn} <- DynamicSupervisor.start_child(__MODULE__, child_spec),
         :ok <- :gen_tcp.controlling_process(socket, conn) do
      {:ok, conn}
    end
  end
end
