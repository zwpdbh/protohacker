defmodule Protohacker.SpeedDaemon.Message.IAmCameraTest do
  use ExUnit.Case

  alias Protohacker.SpeedDaemon.Message.IAmCamera

  describe "decode/1" do
    test "parses IAmCamera{road: 66, mile: 100, limit: 60} from example" do
      # Hex: 80 00 42 00 64 00 3c
      data = <<0x80, 0x00, 0x42, 0x00, 0x64, 0x00, 0x3C>>

      assert {:ok, %IAmCamera{road: 66, mile: 100, limit: 60}, <<>>} = IAmCamera.decode(data)
    end

    test "handles concatenated messages" do
      # Two IAmCamera messages
      data = <<
        # road:1, mile:2, limit:3
        0x80,
        0x00,
        0x01,
        0x00,
        0x02,
        0x00,
        0x03,
        # road:10, mile:11, limit:12
        0x80,
        0x00,
        0x0A,
        0x00,
        0x0B,
        0x00,
        0x0C
      >>

      assert {:ok, %IAmCamera{road: 1, mile: 2, limit: 3}, rest} = IAmCamera.decode(data)
      assert {:ok, %IAmCamera{road: 10, mile: 11, limit: 12}, <<>>} = IAmCamera.decode(rest)
    end

    test "returns error for incomplete header (only type byte)" do
      data = <<0x80>>
      assert {:ok, :incomplete, ^data} = IAmCamera.decode(data)
    end

    test "returns error for incomplete body (missing some fields)" do
      # Has type + 1 u16, needs 3 u16s (6 bytes total after 0x80)
      # only 2 bytes
      data = <<0x80, 0x00, 0x01>>
      assert {:ok, :incomplete, ^data} = IAmCamera.decode(data)
    end
  end

  describe "encode/1" do
    test "encodes IAmCamera{road: 66, mile: 100, limit: 60} correctly" do
      struct = %IAmCamera{road: 66, mile: 100, limit: 60}
      expected = <<0x80, 0x00, 0x42, 0x00, 0x64, 0x00, 0x3C>>
      assert IAmCamera.encode(struct) == expected
    end

    test "encodes IAmCamera{road: 1, mile: 2, limit: 3} correctly" do
      struct = %IAmCamera{road: 1, mile: 2, limit: 3}
      expected = <<0x80, 0x00, 0x01, 0x00, 0x02, 0x00, 0x03>>
      assert IAmCamera.encode(struct) == expected
    end
  end

  describe "round-trip encode/decode" do
    test "encoding then decoding returns equivalent struct" do
      original = %IAmCamera{road: 100, mile: 200, limit: 55}
      encoded = IAmCamera.encode(original)
      assert {:ok, decoded, <<>>} = IAmCamera.decode(encoded)
      assert decoded.road == original.road
      assert decoded.mile == original.mile
      assert decoded.limit == original.limit
    end

    test "decoding then encoding returns original binary" do
      # road:10, mile:11, limit:12
      original_binary = <<0x80, 0x00, 0x0A, 0x00, 0x0B, 0x00, 0x0C>>

      {:ok, %IAmCamera{road: 10, mile: 11, limit: 12} = decoded, <<>>} =
        IAmCamera.decode(original_binary)

      assert IAmCamera.encode(decoded) == original_binary
    end
  end
end
