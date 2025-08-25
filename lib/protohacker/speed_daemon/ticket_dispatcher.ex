defmodule Protohacker.SpeedDaemon.TicketDispatcher do
  use GenServer

  alias Protohacker.SpeedDaemon.Message.IAmDispatcher

  def child_spec(opts) do
    %{
      id: __MODULE__,
      restart: :temporary,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  defstruct [
    :roads,
    :myself,
    :remaining,
    :socket
  ]

  def start_link(opts) do
    %IAmDispatcher{} = dispatcher = Keyword.fetch!(opts, :dispatcher)
    remaining = Keyword.fetch!(opts, :remaining)
    socket = Keyword.fetch!(opts, :socket)

    GenServer.start_link(__MODULE__, {dispatcher, remaining, socket})
  end

  @impl true
  def init({%IAmDispatcher{} = dispatcher, remaining, socket}) do
    state = %__MODULE__{
      roads: dispatcher.roads,
      myself: self(),
      remaining: remaining,
      socket: socket
    }

    {:ok, state, {:continue, :accept}}
  end

  @impl true
  def handle_continue(:accept, %__MODULE__{} = state) do
    :todo
    {:noreply, state, {:continue, :accept}}
  end
end
