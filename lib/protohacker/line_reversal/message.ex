defmodule Protohacker.LineReversal.Message do
  import NimbleParsec

  # client -> server
  defmodule Connect do
    defstruct [
      # non-negative integer
      :session
    ]

    connect_parser =
      ignore(string("/connect/"))
      |> integer(min: 1)
      |> ignore(string("/"))

    defparsec(:parse_connect, connect_parser)
  end

  def decode(data) when is_binary(data) do
    case Connect.parse_connect(data) do
      {:ok, [session], "", _context, _line, _offset} when session >= 0 ->
        {:ok, %Connect{session: session}}

      # Any parse failure
      reason ->
        reason |> dbg()
        :error
    end
  end
end
