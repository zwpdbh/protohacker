defmodule Protohacker.SpeedDaemon.TicketGenerator do
  use GenServer
  require Logger
  alias Phoenix.PubSub

  defstruct [
    :road,
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
    :ok = PubSub.subscribe(:speed_daemon, "camera_road_#{road}")
    {:ok, %__MODULE__{road: road}}
  end

  @doc """
  compute if the same plate have exceed the limit by compute its recent two event: {mile, timestamp}
  """
  @impl true
  def handle_info(
        %{plate: plate, timestamp: timestamp, limit: limit, mile: mile, road: road},
        %__MODULE__{} = state
      )
      when road == state.road do
    day = div(timestamp, 86_400)
    key = {plate, day}

    updated_state =
      case Map.get(state.plate_first, key) do
        nil ->
          # first see that plate, record it
          new_plate_first = Map.put(state.plate_first, key, {mile, timestamp})
          %__MODULE__{state | plate_first: new_plate_first}

        {prev_mile, prev_timestamp} ->
          # second (or later) seen, calculate the speed
          distance_miles = abs(mile - prev_mile)
          time_seconds = abs(timestamp - prev_timestamp)

          speed_mph_float = distance_miles / (time_seconds / 3600)
          speed_mph = round(speed_mph_float)

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
              speed: speed_mph * 100
            }

            Logger.debug("->> generated ticket: #{inspect(ticket)}")

            :ok =
              Phoenix.PubSub.broadcast!(
                :speed_daemon,
                "ticket_generated_road_#{ticket.road}",
                ticket
              )

            new_plate_first = Map.put(state.plate_first, key, {mile, timestamp})
            %{state | plate_first: new_plate_first}
          else
            # too slow, just update the record
            Logger.debug("->> too slow, just update the record")
            new_plate_first = Map.put(state.plate_first, key, {mile, timestamp})
            %{state | plate_first: new_plate_first}
          end
      end

    {:noreply, updated_state}
  end
end
