defmodule Protohacker.LineReversalV2.ClientConnection do
  use GenServer

  def start_link(opts) do
    ip = Keyword.fetch!(opts, :ip)
    port = Keyword.fetch!(opts, :port)
    session_id = Keyword.fetch!(opts, :session_id)

    GenServer.start_link(__MODULE__, {ip, port, session_id}, name: name(ip, port, session_id))
  end

  defstruct [
    :ip,
    :port,
    :session_id
  ]

  @impl true
  def init({ip, port, session_id}) do
    {:ok, %__MODULE__{ip: ip, port: port, session_id: session_id}}
  end

  defp name(ip, port, session_id) do
    {:via, Registry, {Protohacker.LineReversalV2.Registry, {ip, port, session_id}}}
  end
end
