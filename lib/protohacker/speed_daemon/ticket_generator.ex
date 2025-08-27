defmodule Protohacker.SpeedDaemon.TicketGenerator do
  use GenServer
  require Logger
  alias Phoenix.PubSub

  defstruct [
    :road,
    :dispatcher_socket,
    # %{ {plate, day} => {mile, timestamp} }
    plate_first: %{},
    # List of unsent tickets (if no dispatcher)
    pending_tickets: [],
    ticket_sent_records: %{}
  ]

  def child_spec(opts) do
    road = Keyword.fetch!(opts, :road)
    child_id = "#{__MODULE__}#{road}"

    %{
      id: child_id,
      start: {__MODULE__, :start_link, [opts]},
      # REVIEW: what type it could support and why :worker ?
      type: :worker
    }
  end

  def start_link(opts) do
    road = Keyword.fetch!(opts, :road)
    name = via_tuple(road)
    GenServer.start_link(__MODULE__, road, name: name)
  end

  # REVIEW: how registry make sure the unique of TicketGenerator given road
  defp via_tuple(road), do: {:via, Registry, {TicketGeneratorRegistry, road}}

  @impl true
  def init(road) when is_number(road) do
    # subscribe to camera events
    PubSub.subscribe(:speed_daemon, "camera_road_#{road}")
    PubSub.subscribe(:speed_daemon, "ticket_dispatcher_road_#{road}")

    {:ok, %__MODULE__{road: road}}
  end

  @doc """
  compute if the same plate have exceed the limit by compute its recent two event: {mile, timestamp}
  """
  @impl true
  def handle_info(
        %{plate: plate, timestamp: timestamp, limit: limit, mile: mile},
        %__MODULE__{} = state
      ) do
    day = div(timestamp, 86_400)
    key = {plate, day}

    case Map.get(state.plate_first, key) do
      nil ->
        # first see that plate, record it
        new_plate_first = Map.put(state.plate_first, key, {mile, timestamp})
        {:noreply, %__MODULE__{state | plate_first: new_plate_first}}

      {prev_mile, prev_timestamp} ->
        # second (or later) seen, calculate the speed
        distance_miles = abs(mile - prev_mile)
        time_hours = (timestamp - prev_timestamp) / 3_600.0

        if time_hours > 0 do
          # mph × 100
          speed_mph = (distance_miles / time_hours * 3_600_000) |> round()
          speed_mph_float = speed_mph / 100.0

          # Ticket if exceeding limit by >=0.5 mph
          if speed_mph_float >= limit + 0.5 do
            ticket = %Protohacker.SpeedDaemon.Message.Ticket{
              plate: plate,
              road: state.road,
              mile1: min(mile, prev_mile),
              timestamp1: min(timestamp, prev_timestamp),
              mile2: max(mile, prev_mile),
              timestamp2: max(timestamp, prev_timestamp),
              # stored as integer (mph × 100)
              speed: speed_mph
            }

            new_plate_first = Map.put(state.plate_first, key, {mile, timestamp})

            case {state.dispatcher_socket, Map.get(state.ticket_sent_records, key)} do
              # If the dispatcher_socket is available, and ticket_sent_records has no record for that key,
              # Then, send the ticket and update ticket_sent_records.
              {dispatcher_socket, nil} when not is_nil(dispatcher_socket) ->
                ticket_packet = Protohacker.SpeedDaemon.Message.Ticket.encode(ticket)

                case :gen_tcp.send(dispatcher_socket, ticket_packet) do
                  :ok ->
                    new_ticket_sent_records = Map.put(state.ticket_sent_records, key, true)

                    {:noreply,
                     %{
                       state
                       | ticket_sent_records: new_ticket_sent_records,
                         plate_first: new_plate_first
                     }}

                  {:error, _reason} ->
                    new_pending = [{key, ticket}] ++ state.pending_tickets

                    {:noreply,
                     %{
                       state
                       | pending_tickets: new_pending,
                         plate_first: new_plate_first
                     }}
                end

              {_, _} ->
                # For anything else, store ticket in pending, and update plate_first
                new_pending = [{key, ticket}] ++ state.pending_tickets

                {:noreply,
                 %{
                   state
                   | pending_tickets: new_pending,
                     plate_first: new_plate_first
                 }}
            end
          else
            # too slow, just update the record
            new_plate_first = Map.put(state.plate_first, key, {mile, timestamp})
            {:noreply, %{state | plate_first: new_plate_first}}
          end
        else
          # No time passed -- update to latest
          new_plate_first = Map.put(state.plate_first, key, {mile, timestamp})
          {:noreply, %{state | plate_first: new_plate_first}}
        end
    end
  end

  @impl true
  def handle_info(:dispatcher_offline, %__MODULE__{} = state) do
    {:noreply, %{state | dispatcher_socket: nil}}
  end

  @impl true
  def handle_info(
        {:dispatcher_online, dispatcher_socket},
        %__MODULE__{} = state
      ) do
    send(self(), :process_pending_ticket)

    {:noreply, %{state | dispatcher_socket: dispatcher_socket}}
  end

  @impl true
  def handle_info(:process_pending_ticket, %__MODULE__{pending_tickets: []} = state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(
        :process_pending_ticket,
        %__MODULE__{pending_tickets: [{key, ticket} | rest]} = state
      ) do
    ticket_packet = Protohacker.SpeedDaemon.Message.Ticket.encode(ticket)

    with nil <- Map.get(state.ticket_sent_records, key),
         socket <- state.dispatcher_socket,
         :ok <- :gen_tcp.send(socket, ticket_packet) do
      new_ticket_sent_records = Map.put(state.ticket_sent_records, key, true)

      send(self(), :process_pending_ticket)
      {:noreply, %{state | ticket_sent_records: new_ticket_sent_records, pending_tickets: rest}}
    else
      reason ->
        send(self(), :process_pending_ticket)

        Logger.warning("->> process_pending_ticket failed, reason: #{inspect(reason)}")
        {:noreply, state}
    end
  end
end
