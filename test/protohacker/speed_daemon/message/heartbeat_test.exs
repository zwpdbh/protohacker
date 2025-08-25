defmodule Protohacker.SpeedDaemon.Message.HeartbeatTest do
  use ExUnit.Case

  alias Protohacker.SpeedDaemon.Message.WantHeartbeat
  alias Protohacker.SpeedDaemon.Message.Heartbeat

  # ===================================
  # WantHeartbeat (0x40) Tests
  # ===================================

  describe "WantHeartbeat.decode/1" do
    test "parses WantHeartbeat{interval: 10} from example" do
      # Hex: 40 00 00 00 0a
      data = <<0x40, 0x00, 0x00, 0x00, 0x0A>>

      assert {:ok, %WantHeartbeat{interval: 10}, <<>>} = WantHeartbeat.decode(data)
    end

    test "parses WantHeartbeat{interval: 1243} from example" do
      # Hex: 40 00 00 04 db
      data = <<0x40, 0x00, 0x00, 0x04, 0xDB>>

      assert {:ok, %WantHeartbeat{interval: 1243}, <<>>} = WantHeartbeat.decode(data)
    end

    test "parses WantHeartbeat{interval: 0} (disable heartbeats)" do
      data = <<0x40, 0x00, 0x00, 0x00, 0x00>>

      assert {:ok, %WantHeartbeat{interval: 0}, <<>>} = WantHeartbeat.decode(data)
    end

    test "handles concatenated messages" do
      data = <<
        # interval: 10
        0x40,
        0x00,
        0x00,
        0x00,
        0x0A,
        # interval: 20
        0x40,
        0x00,
        0x00,
        0x00,
        0x14
      >>

      assert {:ok, %WantHeartbeat{interval: 10}, rest} = WantHeartbeat.decode(data)
      assert {:ok, %WantHeartbeat{interval: 20}, <<>>} = WantHeartbeat.decode(rest)
    end

    test "returns error for incomplete header (only type byte)" do
      data = <<0x40>>
      assert {:error, :invalid_want_heart__beat_format, ^data} = WantHeartbeat.decode(data)
    end

    test "returns error for incomplete interval (only 3 bytes)" do
      data = <<0x40, 0x00, 0x00, 0x00>>
      assert {:error, :invalid_want_heart__beat_format, ^data} = WantHeartbeat.decode(data)
    end

    test "returns error for wrong message type" do
      data = <<0x41>>
      assert {:error, :unknown_format, ^data} = WantHeartbeat.decode(data)
    end

    test "returns error for empty binary" do
      assert {:error, :unknown_format, <<>>} = WantHeartbeat.decode(<<>>)
    end
  end

  describe "WantHeartbeat.encode/1" do
    test "encodes interval: 10 correctly" do
      struct = %WantHeartbeat{interval: 10}
      expected = <<0x40, 0x00, 0x00, 0x00, 0x0A>>
      assert WantHeartbeat.encode(struct) == expected
    end

    test "encodes interval: 1243 correctly" do
      struct = %WantHeartbeat{interval: 1243}
      expected = <<0x40, 0x00, 0x00, 0x04, 0xDB>>
      assert WantHeartbeat.encode(struct) == expected
    end

    test "encodes interval: 0 correctly" do
      struct = %WantHeartbeat{interval: 0}
      expected = <<0x40, 0x00, 0x00, 0x00, 0x00>>
      assert WantHeartbeat.encode(struct) == expected
    end
  end

  describe "WantHeartbeat round-trip" do
    test "encoding then decoding returns original struct" do
      original = %WantHeartbeat{interval: 123}
      encoded = WantHeartbeat.encode(original)
      assert {:ok, decoded, <<>>} = WantHeartbeat.decode(encoded)
      assert decoded.interval == original.interval
    end

    test "decoding then encoding returns original binary" do
      # interval: 30
      original_binary = <<0x40, 0x00, 0x00, 0x00, 0x1E>>

      {:ok, %WantHeartbeat{interval: 30} = decoded, <<>>} =
        WantHeartbeat.decode(original_binary)

      assert WantHeartbeat.encode(decoded) == original_binary
    end
  end

  # ===================================
  # Heartbeat (0x41) Tests
  # ===================================

  describe "Heartbeat.decode/1" do
    test "parses Heartbeat{} from example" do
      data = <<0x41>>

      assert {:ok, %Heartbeat{}, <<>>} = Heartbeat.decode(data)
    end

    test "handles concatenated messages" do
      data = <<0x41, 0x41, 0x41>>

      assert {:ok, %Heartbeat{}, rest1} = Heartbeat.decode(data)
      assert {:ok, %Heartbeat{}, rest2} = Heartbeat.decode(rest1)
      assert {:ok, %Heartbeat{}, <<>>} = Heartbeat.decode(rest2)
    end

    test "parses Heartbeat{} with trailing data" do
      data = <<0x41, 0x40, 0x00, 0x00, 0x00, 0x0A>>
      assert {:ok, %Heartbeat{}, <<0x40, 0x00, 0x00, 0x00, 0x0A>>} = Heartbeat.decode(data)
    end

    test "returns error for wrong message type" do
      data = <<0x40, 0x00, 0x00, 0x00, 0x0A>>
      assert {:error, :unknown_format, ^data} = Heartbeat.decode(data)
    end

    test "returns error for empty binary" do
      assert {:error, :unknown_format, <<>>} = Heartbeat.decode(<<>>)
    end
  end

  describe "Heartbeat.encode/1" do
    test "encodes Heartbeat{} correctly" do
      expected = <<0x41>>
      assert Heartbeat.encode(%Heartbeat{}) == expected
    end
  end

  describe "Heartbeat round-trip" do
    test "encoding then decoding returns empty struct" do
      encoded = Heartbeat.encode(%Heartbeat{})
      assert {:ok, %Heartbeat{}, <<>>} = Heartbeat.decode(encoded)
    end

    test "decoding then encoding returns <<0x41>>" do
      original_binary = <<0x41>>
      {:ok, %Heartbeat{} = decoded, <<>>} = Heartbeat.decode(original_binary)
      assert Heartbeat.encode(decoded) == original_binary
    end
  end
end
