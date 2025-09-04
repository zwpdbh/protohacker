defmodule Protohacker.SpeedDaemon.TicketManager do
  require Logger
  use GenServer
  alias Protohacker.SpeedDaemon.Message

  defp day(timestamp) do
    div(timestamp, 86400)
  end

  def start_link([] = _opts) do
    GenServer.start_link(__MODULE__, :no_state, name: __MODULE__)
  end

  defstruct [
    :tickets,
    :send_records,
    :previous_plate_event
  ]

  defp ticket_id(%Protohacker.SpeedDaemon.Message.Ticket{} = ticket) do
    "#{ticket.plate}#{day(ticket.timestamp1)}"
  end

  @impl true
  def init(:no_state) do
    # Record previous plate event from camera.
    previous_plate_event = %{}

    # Store the pending tickets to send,
    # key is ticket_id, value is ticket.
    tickets = %{}

    # Store the tickets send record to make sure: only 1 ticket per car per day.
    # key is {ticket.plate, day(timestamp)}, value is ticket
    send_records = %{}

    {:ok,
     %__MODULE__{
       previous_plate_event: previous_plate_event,
       tickets: tickets,
       send_records: send_records
     }}
  end

  @impl true
  def handle_cast(
        {:dispatcher_is_online, %Message.IAmDispatcher{} = dispatcher},
        %__MODULE__{} = state
      ) do
    for {ticket_id, %Message.Ticket{} = ticket} <- state.tickets do
      if ticket.road in dispatcher.roads do
        :ok =
          Phoenix.PubSub.broadcast!(
            :speed_daemon,
            "ticket_generated_road_#{ticket.road}",
            {:ticket_available, ticket_id}
          )
      end
    end

    {:noreply, state}
  end

  @doc """
  compute if the same plate have exceed the limit by compute its recent two event: {mile, timestamp}
  """
  @impl true
  def handle_cast(
        {:plate_event,
         %{plate: plate, timestamp: timestamp, limit: limit, mile: mile, road: road}},
        %__MODULE__{} = state
      ) do
    key = plate

    updated_previous_plate_event =
      case Map.get(state.previous_plate_event, key) do
        nil ->
          # first see that plate, record it
          Map.put(state.previous_plate_event, key, {mile, timestamp})

        {prev_mile, prev_timestamp} when mile == prev_mile and timestamp == prev_timestamp ->
          Logger.warning("exact same mile and timestamp recorded")
          Map.put(state.previous_plate_event, key, {mile, timestamp})

        {prev_mile, prev_timestamp} ->
          # second (or later) seen, calculate the speed
          distance_miles = abs(mile - prev_mile)
          time_seconds = abs(timestamp - prev_timestamp)
          speed_mph = round(distance_miles / (time_seconds / 3600))

          # mile1 and timestamp1 must refer to the earlier of the 2 observations (the smaller timestamp), and mile2 and timestamp2 must refer to the later of the 2 observations (the larger timestamp).
          {mile1, timestamp1, mile2, timestamp2} =
            if prev_timestamp < timestamp do
              {prev_mile, prev_timestamp, mile, timestamp}
            else
              {mile, timestamp, prev_mile, prev_timestamp}
            end

          # Ticket if exceeding limit by >=0.5 mph
          if speed_mph > limit do
            ticket = %Protohacker.SpeedDaemon.Message.Ticket{
              plate: plate,
              road: road,
              mile1: mile1,
              timestamp1: timestamp1,
              mile2: mile2,
              timestamp2: timestamp2,
              speed: speed_mph * 100
            }

            send(self(), {:save_ticket, ticket})
          end

          Map.put(state.previous_plate_event, key, {mile2, timestamp2})
      end

    {:noreply, %{state | previous_plate_event: updated_previous_plate_event}}
  end

  @impl true
  def handle_cast(
        {:send_ticket, ticket_id, socket},
        %__MODULE__{} = state
      ) do
    %Message.Ticket{} = ticket = Map.get(state.tickets, ticket_id)
    ticket_start_day = day(ticket.timestamp1)
    ticket_end_day = day(ticket.timestamp2)

    ticket_send_record_for_start_day =
      Map.get(state.send_records, {ticket.plate, ticket_start_day}, false)

    ticket_send_record_for_end_day =
      Map.get(state.send_records, {ticket.plate, ticket_end_day}, false)

    case {ticket_send_record_for_start_day, ticket_send_record_for_end_day} do
      {false, false} ->
        ticket_packet = ticket |> Message.encode()

        :gen_tcp.send(socket, ticket_packet)
        Logger.debug("sent ticket: #{inspect(ticket)}")

        updated_send_records =
          Map.put(state.send_records, {ticket.plate, ticket_send_record_for_start_day}, true)
          |> Map.put({ticket.plate, ticket_send_record_for_end_day}, true)

        updated_tickets = Map.delete(state.tickets, ticket_id)

        {:noreply,
         %__MODULE__{state | send_records: updated_send_records, tickets: updated_tickets}}

      {_, _} ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(
        {:save_ticket, %Protohacker.SpeedDaemon.Message.Ticket{} = ticket},
        %__MODULE__{} = state
      ) do
    ticket_id = ticket_id(ticket)
    updated_tickets = Map.put(state.tickets, ticket_id, ticket)

    # Notifice dispatcher that
    :ok =
      Phoenix.PubSub.broadcast!(
        :speed_daemon,
        "ticket_generated_road_#{ticket.road}",
        {:ticket_available, ticket_id}
      )

    {:noreply, %{state | tickets: updated_tickets}}
  end

  def save_ticket(ticket) do
    GenServer.cast(__MODULE__, {:save_ticket, ticket})
  end

  def send_ticket_to_socket(ticket_id, socket) do
    GenServer.cast(__MODULE__, {:send_ticket, ticket_id, socket})
  end

  def dispatcher_is_online(%Protohacker.SpeedDaemon.Message.IAmDispatcher{} = dispatcher) do
    GenServer.cast(__MODULE__, {:dispatcher_is_online, dispatcher})
  end

  def record_plate(plate_event) do
    GenServer.cast(__MODULE__, {:plate_event, plate_event})
  end
end
