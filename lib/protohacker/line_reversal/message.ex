defmodule Protohacker.LineReversal.Message do
  import NimbleParsec

  @max_int 2_147_483_648

  # ------------------------
  # Connect Message
  # ------------------------
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

  # ------------------------
  # Data Message
  # ------------------------
  defmodule Data do
    defstruct [
      :session,
      :pos,
      :packet
    ]

    # Parse /data/<session>/<pos>/<data>/
    # We'll grab <data> as raw string until final "/"
    data_parser =
      ignore(string("/data/"))
      |> integer(min: 1)
      |> ignore(string("/"))
      |> integer(min: 1)
      |> ignore(string("/"))
      # grabs everything until next "/"
      |> utf8_string([not: ?/], min: 0)
      |> ignore(string("/"))

    defparsec(:parse_data, data_parser)

    # Unescape: replace "\/" -> "/", "\\" -> "\"
    def unescape(binary) do
      binary
      |> String.replace("\\/", "/", global: true)
      |> String.replace("\\\\", "\\", global: true)
    end
  end

  # ------------------------
  # Decode
  # ------------------------

  def decode(data) when is_binary(data) do
    # Validate overall structure: starts and ends with "/"
    cond do
      not String.starts_with?(data, "/") or not String.ends_with?(data, "/") ->
        :error

      byte_size(data) >= 1000 ->
        :error

      true ->
        decode_message(data)
    end
  end

  defp decode_message(data) do
    case try_parse_connect(data) do
      {:ok, connect} -> {:ok, connect}
      :error -> try_parse_data(data)
    end
  end

  defp try_parse_connect(data) do
    case Connect.parse_connect(data) do
      {:ok, [session], "", _, _, _} when session >= 0 and session < @max_int ->
        {:ok, %Connect{session: session}}

      _ ->
        :error
    end
  end

  defp try_parse_data(data) do
    case Data.parse_data(data) do
      {:ok, [session, pos, raw_data], "", _, _, _}
      when session >= 0 and session < @max_int and pos >= 0 and pos < @max_int ->
        unescaped = Data.unescape(raw_data)
        {:ok, %Data{session: session, pos: pos, packet: unescaped}}

      _ ->
        :error
    end
  end
end
