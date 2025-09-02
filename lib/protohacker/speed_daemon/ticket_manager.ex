defmodule Protohacker.SpeedDaemon.TicketManager do
  require Logger
  use GenServer

  def start_link([] = _opts) do
    GenServer.start_link(__MODULE__, :no_state, name: __MODULE__)
  end

  defstruct [
    :tickets,
    :send_record
  ]

  @impl true
  def init(:no_state) do
    {:ok, %__MODULE__{tickets: %{}, send_record: %{}}}
  end

  @impl true
  def handle_call(
        {:save_ticket, %Protohacker.SpeedDaemon.Message.Ticket{} = ticket},
        _from,
        %__MODULE__{} = state
      ) do
    udpated_tickets = Map.put(state.tickets, ticket.plate, ticket)
    updated_send_record = Map.put(state.send_record, ticket.plate, 0)

    Phoenix.PubSub.broadcast!(:speed_daemon, "ticket_generated_road_#{ticket.road}", ticket)
    {:reply, :ok, %{state | tickets: udpated_tickets, send_record: updated_send_record}}
  end

  @impl true
  def handle_cast(
        {:send_ticket, %Protohacker.SpeedDaemon.Message.Ticket{} = ticket, socket},
        %__MODULE__{} = state
      ) do
    case Map.get(state.send_record, ticket.plate) do
      0 ->
        :gen_tcp.send(
          socket,
          Protohacker.SpeedDaemon.Message.Ticket.encode(ticket)
        )

        Logger.info("->> send ticket: #{inspect(ticket)}")

        updated_send_record = Map.put(state.send_record, ticket.plate, 1)
        {:noreply, %{state | send_record: updated_send_record}}

      _ ->
        Logger.warning("same ticket has already been sent")
        {:noreply, state}
    end
  end

  def save_ticket(ticket) do
    GenServer.call(__MODULE__, {:save_ticket, ticket})
  end

  def send_ticket_to_socket(%Protohacker.SpeedDaemon.Message.Ticket{} = ticket, socket) do
    GenServer.cast(__MODULE__, {:send_ticket, ticket, socket})
  end
end
