defmodule Protohacker.SpeedDaemon.TicketGenerator do
  use GenServer
  alias Phoenix.PubSub

  defstruct [
    :road,
    :speed_limit
  ]

  def child_spec(opts) do
    road = Keyword.fetch!(opts, :road)
    child_id = "#{__MODULE__}#{road}"

    %{
      id: child_id,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(opts) do
    road = Keyword.fetch!(opts, :road)

    GenServer.start_link(__MODULE__, road, name: via_tuple(road))
  end

  defp via_tuple(road), do: {:via, Registry, {TicketGeneratorRegistry, road}}

  @impl true
  def init(road) when is_number(road) do
    PubSub.subscribe(:speed_daemon, "camera_road_#{road}")

    {:ok, %__MODULE__{road: road, speed_limit: nil}}
  end

  @doc """
  compute if the same plate have exceed the limit by compute its recent two event: {mile, timestamp}
  """
  @impl true
  def handle_info(
        %{plate: plate, timestamp: timestamp, limit: limit, mile: mile},
        %__MODULE__{} = state
      ) do
    {:noreply, state}
  end
end
