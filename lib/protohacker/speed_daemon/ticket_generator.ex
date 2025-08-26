defmodule Protohacker.SpeedDaemon.TicketGenerator do
  use GenServer
  alias Phoenix.PubSub

  defstruct [
    :road,
    # %{ {plate, day} => {mile, timestamp} }
    plate_first: %{},
    # List of unsent tickets (if no dispatcher)
    pending_tickets: []
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
        nil
        {:noreply, state}
    end
  end
end
