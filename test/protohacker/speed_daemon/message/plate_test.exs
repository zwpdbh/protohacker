defmodule Protohacker.SpeedDaemon.Message.PlateTest do
  use ExUnit.Case

  alias Protohacker.SpeedDaemon.Message.Plate

  describe "decode/1" do
    test "parses Plate{plate: 'UN1X', timestamp: 1000} from example" do
      # Hex: 20 04 55 4e 31 58 00 00 03 e8
      data = <<0x20, 0x04, 0x55, 0x4E, 0x31, 0x58, 0x00, 0x00, 0x03, 0xE8>>

      assert {:ok, %Plate{plate: "UN1X", timestamp: 1000}, <<>>} = Plate.decode(data)
    end

    test "parses Plate{plate: 'RE05BKG', timestamp: 123456} from example" do
      # Hex: 20 07 52 45 30 35 42 4b 47 00 01 e2 40
      data = <<0x20, 0x07, 0x52, 0x45, 0x30, 0x35, 0x42, 0x4B, 0x47, 0x00, 0x01, 0xE2, 0x40>>

      assert {:ok, %Plate{plate: "RE05BKG", timestamp: 123_456}, <<>>} = Plate.decode(data)
    end

    test "handles concatenated messages" do
      # Plate{"A1", 100}, Plate{"B2", 200}
      data = <<
        # A1 @ 100
        0x20,
        0x02,
        0x41,
        0x31,
        0x00,
        0x00,
        0x00,
        0x64,
        # B2 @ 200
        0x20,
        0x02,
        0x42,
        0x32,
        0x00,
        0x00,
        0x00,
        0xC8
      >>

      assert {:ok, %Plate{plate: "A1", timestamp: 100}, rest} = Plate.decode(data)
      assert {:ok, %Plate{plate: "B2", timestamp: 200}, <<>>} = Plate.decode(rest)
    end

    test "returns error for incomplete header (only type byte)" do
      data = <<0x20>>
      assert {:ok, :incomplete, ^data} = Plate.decode(data)
    end

    test "returns error for incomplete plate length (missing string bytes)" do
      # Has type + length (4), but no string
      data = <<0x20, 0x04>>
      assert {:ok, :incomplete, ^data} = Plate.decode(data)
    end

    test "returns error for incomplete plate string" do
      # Wants 4 chars, but only provides 2
      data = <<0x20, 0x04, 0x41, 0x42>>
      assert {:ok, :incomplete, ^data} = Plate.decode(data)
    end

    test "returns error for incomplete timestamp (only 3 bytes)" do
      # Plate{"X", 123} — but missing one byte of timestamp
      data = <<0x20, 0x01, 0x58, 0x00, 0x00, 0x00>>
      assert {:ok, :incomplete, ^data} = Plate.decode(data)
    end
  end

  describe "encode/1" do
    test "encodes Plate{plate: 'UN1X', timestamp: 1000} correctly" do
      plate = %Plate{plate: "UN1X", timestamp: 1000}
      expected = <<0x20, 0x04, 0x55, 0x4E, 0x31, 0x58, 0x00, 0x00, 0x03, 0xE8>>
      assert Plate.encode(plate) == expected
    end

    test "encodes Plate{plate: 'RE05BKG', timestamp: 123456} correctly" do
      plate = %Plate{plate: "RE05BKG", timestamp: 123_456}
      expected = <<0x20, 0x07, 0x52, 0x45, 0x30, 0x35, 0x42, 0x4B, 0x47, 0x00, 0x01, 0xE2, 0x40>>
      assert Plate.encode(plate) == expected
    end

    test "encodes short plate correctly" do
      plate = %Plate{plate: "X", timestamp: 1}
      expected = <<0x20, 0x01, 0x58, 0x00, 0x00, 0x00, 0x01>>
      assert Plate.encode(plate) == expected
    end

    test "handles plate with non-ASCII characters (allowed as binary)" do
      # Protocol says ASCII, but encode should accept any binary
      plate = %Plate{plate: "CAFE\xFF", timestamp: 999}
      encoded = Plate.encode(plate)
      assert <<0x20, 0x05, "CAFE\xFF"::binary, 0x00, 0x00, 0x03, 0xE7>> = encoded
    end
  end

  describe "round-trip encode/decode" do
    test "encoding then decoding returns original message" do
      original = %Plate{plate: "ABC123", timestamp: 5000}
      encoded = Plate.encode(original)
      assert {:ok, %Plate{plate: "ABC123", timestamp: 5000}, <<>>} = Plate.decode(encoded)
    end

    test "decoding then encoding returns original binary" do
      # Plate{"FOO", 10}
      original_binary = <<0x20, 0x03, 0x46, 0x4F, 0x4F, 0x00, 0x00, 0x00, 0x0A>>

      assert {:ok, %Plate{plate: "FOO", timestamp: 10}, <<>>} = Plate.decode(original_binary)

      assert Plate.encode(%Plate{plate: "FOO", timestamp: 10}) == original_binary
    end
  end

  describe "error handling on invalid data" do
    test "rescues on invalid string (non-printable, but still valid binary)" do
      # Binary is valid even if not printable — to_string should still work
      data = <<0x20, 0x02, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x01>>
      assert {:error, {:malformed, "plate contains non valid ASCII"}} = Plate.decode(data)

      # Note: `to_string(<<255,255>>)` returns a string with invalid char codes — but it's still a string
    end
  end
end
