defmodule Protohacker.LineReversal.LRCP.Protocol do
  @max_int 2_147_483_648

  @type session_id() :: integer()

  @type packet() ::
          {:connect, session_id()}
          | {:close, session_id()}
          | {:data, session_id(), integer(), binary()}
          | {:ack, session_id(), integer()}

  @spec parse_packet(binary()) :: {:ok, packet()} | :error
  def parse_packet(data) do
    # REVIEW: the usage of ? which is used to get the binary representation of a
    # singal character is it as same as <<"/", rest::binary>>
    with <<?/, rest::binary>> <- data,
         {:ok, parts} <- split(rest, _acc = [], _part = <<>>) do
      parse_packet_fields(parts)
    else
      _other -> :error
    end
  end

  # ------------------------
  # split
  # ------------------------
  defp split(<<>>, _acc, _part), do: :error

  defp split(<<"/">> = _end, acc, part) do
    {:ok, Enum.reverse([part | acc])}
  end

  # This is the case the packet contains "\/", we treat them as whole normal data
  defp split(<<"\\/", rest::binary>>, acc, part) do
    split(rest, acc, <<part::binary, "\\/">>)
  end

  defp split(<<"/", rest::binary>>, acc, part) do
    split(rest, [part | acc], <<>>)
  end

  defp split(<<char, rest::binary>>, acc, part) do
    split(rest, acc, <<part::binary, char>>)
  end

  # ------------------------
  # parse_packet_fields
  # ------------------------

  defp parse_packet_fields(["ack", session_id, position]) do
    with {:ok, session_id} <- parse_int(session_id),
         {:ok, position} <- parse_int(position) do
      {:ok, {:ack, session_id, position}}
    end
  end

  defp parse_packet_fields(["close", session_id]) do
    with {:ok, session_id} <- parse_int(session_id) do
      {:ok, {:close, session_id}}
    end
  end

  defp parse_packet_fields(["data", session_id, pos, data]) do
    with {:ok, session_id} <- parse_int(session_id),
         {:ok, pos} <- parse_int(pos) do
      {:ok, {:data, session_id, pos, data}}
    end
  end

  defp parse_packet_fields(["connect", session_id]) do
    with {:ok, session_id} <- parse_int(session_id) do
      {:ok, {:connect, session_id}}
    end
  end

  defp parse_packet_fields(_other) do
    :error
  end

  # ------------------------
  # session id
  # ------------------------
  def session_id({:connect, session_id}), do: session_id
  def session_id({:close, session_id}), do: session_id
  def session_id({:data, session_id, _position, _data}), do: session_id
  def session_id({:ack, session_id, _position}), do: session_id

  defp parse_int(bin) do
    case Integer.parse(bin) do
      {int, ""} when int < @max_int -> {:ok, int}
      _ -> :error
    end
  end

  # ------------------------
  # My Notes
  # ------------------------

  # If a peer receives an ACK with position N, it means:
  # I have received all bytes up to (and including) position N-1.
  # The next byte I expect is at position N.
end
