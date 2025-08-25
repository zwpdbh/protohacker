defmodule Protohacker.SpeedDaemon.Message do
  @moduledoc """
  1. Each message starts with a single u8 specifying the message type.
  2. There is no message delimiter. Messages are simply concatenated together with no padding.

  Type of messages
  - 0x10: Error (Server->Client)
  - 0x20: Plate (Client->Server)
  - 0x21: Ticket (Server->Client)
  - 0x40: WantHeartbeat (Client->Server)
  - 0x41: Heartbeat (Server->Client)
  - 0x80: IAmCamera (Client->Server)
  - 0x81: IAmDispatcher (Client->Server)

  Notice:
  A string of characters in a length-prefixed format.
  """

  defmodule Error do
    @moduledoc """
    To check if a binary contains Error message, we need to
    1. Check the first byte to see if it is 0x10.
    2. If so, check the next byte as u8 which represent the lengh of the str, say n.
    3. The next n bytes are ASCII character codes.
    """

    defstruct [
      :msg
    ]

    @doc """
    Parse binary data to extract 0x10: Error (Server->Client)

    Returns:
      {:ok, %Error{msg: string}, rest}  - successfully parsed, with leftover data
      {:error, remaining}                - invalid or incomplete message

    Note: The protocol allows empty strings (length 0).
    """
    def decode(
          <<0x10, msg_len::unsigned-integer-size(8), msg_bytes::binary-size(msg_len),
            remaining::binary>>
        ) do
      # Convert binary to string (assumes ASCII, as per protocol)
      if Protohacker.SpeedDaemon.Message.valid_ascii?(msg_bytes) do
        decoded_msg = msg_bytes |> to_string()
        {:ok, %__MODULE__{msg: decoded_msg}, remaining}
      else
        {:error, :invalid_string, %{msg: msg_bytes}}
      end
    end

    # Handle incomplete or malformed data
    def decode(<<0x10, msg_len, rest::binary>>) do
      # If we don't have enough data for the string
      if byte_size(rest) < msg_len do
        {:error, :incomplete, <<0x10, msg_len>> <> rest}
      else
        # This case should not happen — means pattern didn't match
        {:error, :malformed, <<0x10, msg_len>> <> rest}
      end
    end

    def decode(<<0x10>>) do
      {:error, :incomplete, <<0x10>>}
    end

    # Wrong message type
    def decode(data) when is_binary(data) do
      {:error, :invalid_type, data}
    end

    def encode(msg) when is_binary(msg) do
      <<0x10, byte_size(msg)::unsigned-integer-8, msg::binary>>
    end
  end

  defmodule Plate do
    @moduledoc """
    1. First byte is 0x20,
    2. Followed by plate:str,
    3. Then timestamp:u32
    """

    defstruct [
      :plate,
      :timestamp
    ]

    def decode(
          <<0x20, plate_len::unsigned-integer-8, plate_str_bytes::binary-size(plate_len),
            timestamp::unsigned-integer-32, remaining::binary>> = data
        )
        when is_binary(data) do
      if Protohacker.SpeedDaemon.Message.valid_ascii?(plate_str_bytes) do
        plate = plate_str_bytes |> to_string()
        {:ok, %__MODULE__{plate: plate, timestamp: timestamp}, remaining}
      else
        {:error, :invalid_ascii, %{plate: plate_str_bytes}}
      end
    end

    def decode(<<0x20, _::binary>> = data) do
      {:error, :invalid_plate_format, data}
    end

    def decode(data) do
      {:error, :unknown_format, data}
    end

    def encode(%__MODULE__{} = plate_info) do
      <<0x20, byte_size(plate_info.plate), plate_info.plate::binary,
        plate_info.timestamp::unsigned-integer-32>>
    end
  end

  defmodule Ticket do
    @moduledoc """
    0x21: Ticket (Server->Client)

    Hexadecimal:            Decoded:
    21                      Ticket{
    04 55 4e 31 58              plate: "UN1X",
    00 42                       road: 66,
    00 64                       mile1: 100,
    00 01 e2 40                 timestamp1: 123456,
    00 6e                       mile2: 110,
    00 01 e3 a8                 timestamp2: 123816,
    27 10                       speed: 10000,
                        }
    """
    defstruct [
      # str
      :plate,
      # u16
      :road,
      # u16
      :mile1,
      # u32
      :timestamp1,
      # u16
      :mile2,
      # u32
      :timestamp2,
      # u16
      :speed
    ]

    def decode(
          <<0x21, plate_str_len::unsigned-integer-8, plate_str_bytes::binary-size(plate_str_len),
            road::unsigned-integer-16, mile1::unsigned-integer-16,
            timestamp1::unsigned-integer-32, mile2::unsigned-integer-16,
            timestamp2::unsigned-integer-32, speed::unsigned-integer-16,
            remaining::binary>> = data
        )
        when is_binary(data) do
      if Protohacker.SpeedDaemon.Message.valid_ascii?(plate_str_bytes) do
        plate = to_string(plate_str_bytes)

        {:ok,
         %__MODULE__{
           plate: plate,
           road: road,
           mile1: mile1,
           timestamp1: timestamp1,
           mile2: mile2,
           timestamp2: timestamp2,
           speed: speed
         }, remaining}
      else
        {:error, :invalid_ascii, %{plate: plate_str_bytes}}
      end
    end

    def decode(<<0x21, _::binary>> = data) do
      {:error, :invalid_ticket_format, data}
    end

    def decode(data) do
      {:error, :unknown_format, data}
    end

    def encode(%__MODULE__{} = data) do
      <<0x21, byte_size(data.plate)::unsigned-integer-8, data.plate::binary,
        data.road::unsigned-integer-16, data.mile1::unsigned-integer-16,
        data.timestamp1::unsigned-integer-32, data.mile2::unsigned-integer-16,
        data.timestamp2::unsigned-integer-32, data.speed::unsigned-integer-16>>
    end
  end

  defmodule WantHeartbeat do
    @moduledoc """
    0x40: WantHeartbeat (Client->Server)

    Hexadecimal:    Decoded:
    40              WantHeartbeat{
    00 00 00 0a         interval: 10
                }

    """

    defstruct [
      # deciseconds which there are 10 per second
      # For example, So an interval of "25" would mean a Heartbeat message every 2.5 seconds.
      :interval
    ]

    def decode(<<0x40, interval::unsigned-integer-32, remaining::binary>> = data)
        when is_binary(data) do
      {:ok, %__MODULE__{interval: interval}, remaining}
    end

    def decode(<<0x40, _::binary>> = data) when is_binary(data) do
      {:error, :invalid_want_heart__beat_format, data}
    end

    def decode(data) do
      {:error, :unknown_format, data}
    end

    def encode(%__MODULE__{} = data) do
      <<0x40, data.interval::unsigned-integer-32>>
    end
  end

  defmodule Heartbeat do
    @moduledoc """
    0x41: Heartbeat (Server->Client)

    Hexadecimal:    Decoded:
    41              Heartbeat{}
    """
    defstruct []

    def decode(<<0x41, remaining::binary>> = data) when is_binary(data) do
      {:ok, %__MODULE__{}, remaining}
    end

    def decode(data) when is_binary(data) do
      {:error, :unknown_format, data}
    end

    def encode(%__MODULE__{} = _data) do
      <<0x41>>
    end
  end

  defmodule IAmCamera do
    @moduledoc """
    0x80: IAmCamera (Client->Server)

    Hexadecimal:    Decoded:
    80              IAmCamera{
    00 42               road: 66,
    00 64               mile: 100,
    00 3c               limit: 60,
                }
    """
    defstruct [
      :road,
      :mile,
      # miles per hour
      :limit
    ]

    def decode(
          <<0x80, road::unsigned-integer-16, mile::unsigned-16, limit::unsigned-16,
            remaining::binary>> = data
        )
        when is_binary(data) do
      {:ok, %__MODULE__{road: road, mile: mile, limit: limit}, remaining}
    end

    def decode(<<0x80, _::binary>> = data) when is_binary(data) do
      {:error, :invalid_format, data}
    end

    def decode(data) when is_binary(data) do
      {:error, :unknown_format, data}
    end

    def encode(%__MODULE__{} = data) do
      <<0x80, data.road::unsigned-16, data.mile::unsigned-16, data.limit::unsigned-16>>
    end
  end

  defmodule IAmDispatcher do
    @moduledoc """
    numroads: u8
    roads: [u16] (array of u16)

    The numroads field says how many roads this dispatcher is responsible for,
    and the roads field contains the road numbers.

    0x81: IAmDispatcher (Client->Server)

    Hexadecimal:    Decoded:
    81              IAmDispatcher{
    01                  roads: [
    00 42                   66
                    ]
                }

    81              IAmDispatcher{
    03                  roads: [
    00 42                   66,
    01 70                   368,
    13 88                   5000
                    ]
                }
    """
    defstruct [
      :numroads,
      :roads
    ]

    def decode(
          <<0x81, numroads::unsigned-8, roads::binary-size(2 * numroads), remaining::binary>> =
            data
        )
        when is_binary(data) do
      roads = parse_binary_to_array_of_road(roads, [])

      {:ok, %__MODULE__{numroads: numroads, roads: roads}, remaining}
    end

    def decode(<<0x81, _::binary>> = data) when is_binary(data) do
      {:error, :invalid_format, data}
    end

    def decode(data) do
      {:error, :unknow_format, data}
    end

    defp parse_binary_to_array_of_road(<<road::unsigned-16, remaining::binary>> = data, acc)
         when is_binary(data) do
      parse_binary_to_array_of_road(remaining, acc ++ [road])
    end

    defp parse_binary_to_array_of_road(<<>> = data, acc)
         when is_binary(data) do
      acc
    end

    def encode(%__MODULE__{} = data) do
      roads_binary = encode_array_of_roads_to_binary(data.roads, <<>>)
      <<0x81, data.numroads::unsigned-8, roads_binary::binary>>
    end

    def encode(_ = data) do
      raise "expect #{__MODULE__}, but got: #{inspect(data)}"
    end

    defp encode_array_of_roads_to_binary([first | rest] = _roads, acc) do
      <<acc::binary, first::unsigned-16>>
      encode_array_of_roads_to_binary(rest, <<acc::binary, first::unsigned-16>>)
    end

    defp encode_array_of_roads_to_binary([], acc) do
      acc
    end
  end

  def valid_ascii?(binary) do
    :binary.bin_to_list(binary) |> Enum.all?(&(&1 in 0..127))
  end
end
