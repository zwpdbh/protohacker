defmodule Protohacker.SpeedDaemon.TicketGenerator do
  use GenServer
  require Logger

  def start_link([] = _opts) do
    GenServer.start_link(__MODULE__, :no_state, name: __MODULE__)
  end

  defstruct [
    # %{ {plate, day} => {mile, timestamp} }
    plate_first: %{}
  ]

  @impl true
  def init(:no_state) do
    :ok = Phoenix.PubSub.subscribe(:speed_daemon, "camera")
    {:ok, %__MODULE__{}}
  end

  @doc """
  compute if the same plate have exceed the limit by compute its recent two event: {mile, timestamp}
  """
  @impl true
  def handle_info(
        %{plate: plate, timestamp: timestamp, limit: limit, mile: mile, road: road},
        %__MODULE__{} = state
      ) do
    day = div(timestamp, 86_400)
    key = {plate, day}

    updated_plate_first =
      case Map.get(state.plate_first, key) do
        nil ->
          # first see that plate, record it
          Map.put(state.plate_first, key, {mile, timestamp})

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
              road: road,
              mile1: min(mile, prev_mile),
              timestamp1: min(timestamp, prev_timestamp),
              mile2: max(mile, prev_mile),
              timestamp2: max(timestamp, prev_timestamp),
              # stored as integer (mph × 100)
              speed: speed_mph * 100
            }

            :ok = Protohacker.SpeedDaemon.TicketManager.save_ticket(ticket)
            Logger.debug("->> generated ticket: #{inspect(ticket)}")
          else
            # too slow, just update the record
            Logger.debug("->> too slow, just update the record")
          end

          Map.put(state.plate_first, key, {mile, timestamp})
      end

    {:noreply, %{state | plate_first: updated_plate_first}}
  end
end
