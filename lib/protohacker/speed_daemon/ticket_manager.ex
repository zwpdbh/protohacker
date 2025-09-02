defmodule Protohacker.SpeedDaemon.TicketManager do
  require Logger
  use GenServer

  def start_link([] = _opts) do
    GenServer.start_link(__MODULE__, :no_state, name: __MODULE__)
  end

  defstruct [
    :tickets
  ]

  @impl true
  def init(:no_state) do
    {:ok, %__MODULE__{tickets: %{}}}
  end

  @impl true
  def handle_call(
        {:save_ticket, ticket},
        _from,
        %__MODULE__{tickets: tickets} = state
      ) do
    udpated_tickets =
      case Map.get(tickets, ticket) do
        nil ->
          Map.put(tickets, ticket, 0)

        _ ->
          tickets
      end

    {:reply, :ok, %{state | tickets: udpated_tickets}}
  end

  @impl true
  def handle_cast({:send_ticket, ticket, socket}, %__MODULE__{} = state) do
    case Map.get(state.tickets, ticket) do
      0 ->
        :gen_tcp.send(
          socket,
          Protohacker.SpeedDaemon.Message.Ticket.encode(ticket)
        )

        updated_tickets = Map.put(state.tickets, ticket, 1)
        {:noreply, %{state | tickets: updated_tickets}}

      _ ->
        Logger.warning("same ticket has already been sent")
        {:noreply, state}
    end
  end

  def save_ticket(ticket) do
    GenServer.call(__MODULE__, {:save_ticket, ticket})
  end

  def send_ticket_to_socket(ticket, socket) do
    GenServer.cast(__MODULE__, {:send_ticket, ticket, socket})
  end
end
