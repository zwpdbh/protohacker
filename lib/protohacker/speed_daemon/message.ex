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
    def decode(<<0x10, len::unsigned-integer-8, rest::binary>>) when is_binary(rest) do
      # String length must be 0..255 (u8), which it always is, but check data size
      if byte_size(rest) >= len do
        <<str_bytes::binary-size(len), remaining::binary>> = rest

        # Convert binary to string (assumes valid ASCII, per protocol)
        msg = :binary.bin_to_list(str_bytes) |> List.to_string()

        {:ok, %__MODULE__{msg: msg}, remaining}
      else
        # Not enough data to read `len` bytes — incomplete message
        {:error, "not enough data to read", <<0x10, len>> <> rest}
      end
    end

    # Catch-all: doesn't start with 0x10 or invalid binary
    def decode(data) when is_binary(data) do
      {:error, "invalid format", data}
    end

    def encode(msg) when is_binary(msg) do
      <<0x10, byte_size(msg)::unsigned-integer-8, msg::binary>>
    end
  end
end
