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
          <<0x10, msg_len::unsigned-integer-size(8), msg::binary-size(msg_len),
            remaining::binary>>
        ) do
      # Convert binary to string (assumes ASCII, as per protocol)
      try do
        decoded_msg = msg |> to_string()
        {:ok, %__MODULE__{msg: decoded_msg}, remaining}
      rescue
        _ -> {:error, :invalid_string, <<0x10, msg_len>> <> msg <> remaining}
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
      try do
        plate = plate_str_bytes |> to_string()
        {:ok, %__MODULE__{plate: plate, timestamp: timestamp}, remaining}
      rescue
        _ ->
          {:error, :invalid_value, %{plate: plate_str_bytes, timestamp: timestamp}}
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
end
