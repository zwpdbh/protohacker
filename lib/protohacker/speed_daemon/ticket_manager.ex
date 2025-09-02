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
    # key is {ticket.plate, day}, value is ticket
    tickets = %{}

    # key is {ticket.plate, day}, value is integer represent the count of number ticket has been sent to client.
    send_records = %{}
    {:ok, %__MODULE__{tickets: tickets, send_record: send_records}}
  end

  @impl true
  def handle_cast(
        {:save_ticket, %Protohacker.SpeedDaemon.Message.Ticket{} = ticket},
        %__MODULE__{} = state
      ) do
    keys = generate_keys_from_ticket(ticket)

    udpated_tickets =
      keys
      |> Enum.map(fn each_key -> {each_key, ticket} end)
      |> Enum.into(state.tickets)

    updated_send_record =
      keys
      |> Enum.reduce(state.send_record, fn each_key, send_records ->
        case Map.get(send_records, each_key) do
          nil ->
            Map.put(send_records, each_key, 0)

          _ ->
            send_records
        end
      end)

    {:noreply, %{state | tickets: udpated_tickets, send_record: updated_send_record}}
  end

  @impl true
  def handle_cast(
        {:send_ticket, %Protohacker.SpeedDaemon.Message.Ticket{} = ticket, socket},
        %__MODULE__{} = state
      ) do
    keys = generate_keys_from_ticket(ticket)

    updated_send_record =
      keys
      |> Enum.reduce(state.send_record, fn each_key, send_records ->
        case Map.get(send_records, each_key) do
          0 ->
            :gen_tcp.send(
              socket,
              Protohacker.SpeedDaemon.Message.Ticket.encode(ticket)
            )

            Logger.info("->> send_ticket, key: #{inspect(each_key)}, ticket: #{inspect(ticket)}")
            Map.put(send_records, each_key, 1)

          _ ->
            Logger.warning("same ticket has already been sent")
        end
      end)

    {:noreply, %{state | send_record: updated_send_record}}
  end

  @impl true
  def handle_cast(
        {:dispatcher_is_online, %Protohacker.SpeedDaemon.Message.IAmDispatcher{} = dispatcher},
        %__MODULE__{} = state
      ) do
    for {_key, %Protohacker.SpeedDaemon.Message.Ticket{} = ticket} <- state.tickets do
      with true <- ticket.road in dispatcher.roads,
           0 <- Map.get(state.send_record, {ticket.plate, ticket.road}) do
        :ok =
          Phoenix.PubSub.broadcast!(:speed_daemon, "ticket_generated_road_#{ticket.road}", ticket)
      end
    end

    {:noreply, state}
  end

  # Where a ticket spans multiple days, the ticket is considered to apply to every day from the start to the end day,
  # including the end day. This means that where there is a choice of observations to include in a ticket, \
  # it is sometimes possible for the server to choose either to send a ticket for each day, or to send a single
  # ticket that spans both days: either behaviour is acceptable. (But to maximise revenues, you may prefer to send as many tickets as possible).
  defp generate_keys_from_ticket(%Protohacker.SpeedDaemon.Message.Ticket{} = ticket) do
    n = 86400
    day1 = div(ticket.timestamp1, n)
    day2 = div(ticket.timestamp2, n)

    day1..day2
    |> Enum.map(fn each_day -> {ticket.plate, each_day} end)
  end

  def save_ticket(ticket) do
    GenServer.cast(__MODULE__, {:save_ticket, ticket})
  end

  def send_ticket_to_socket(%Protohacker.SpeedDaemon.Message.Ticket{} = ticket, socket) do
    GenServer.cast(__MODULE__, {:send_ticket, ticket, socket})
  end

  def dispatcher_is_online(%Protohacker.SpeedDaemon.Message.IAmDispatcher{} = dispatcher) do
    GenServer.cast(__MODULE__, {:dispatcher_is_online, dispatcher})
  end
end
