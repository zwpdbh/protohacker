defmodule Protohacker.SpeedDaemon.Message.IAmDispatcherTest do
  use ExUnit.Case

  alias Protohacker.SpeedDaemon.Message.IAmDispatcher

  describe "decode/1" do
    test "parses IAmDispatcher{roads: [66]} from example" do
      # Hex: 81 01 00 42
      data = <<0x81, 0x01, 0x00, 0x42>>

      assert {:ok, %IAmDispatcher{numroads: 1, roads: [66]}, <<>>} = IAmDispatcher.decode(data)
    end

    test "parses IAmDispatcher{roads: [66, 368, 5000]} from example" do
      # Hex: 81 03 00 42 01 70 13 88
      data = <<0x81, 0x03, 0x00, 0x42, 0x01, 0x70, 0x13, 0x88>>

      assert {:ok, %IAmDispatcher{numroads: 3, roads: [66, 368, 5000]}, <<>>} =
               IAmDispatcher.decode(data)
    end

    test "parses IAmDispatcher with zero roads" do
      # Hex: 81 00
      data = <<0x81, 0x00>>

      assert {:ok, %IAmDispatcher{numroads: 0, roads: []}, <<>>} = IAmDispatcher.decode(data)
    end

    test "handles concatenated messages" do
      # Two IAmDispatcher messages
      data = <<
        # First: roads [100]
        0x81,
        0x01,
        0x00,
        0x64,
        # Second: roads [200, 300]
        0x81,
        0x02,
        0x00,
        0xC8,
        0x01,
        0x2C
      >>

      assert {:ok, %IAmDispatcher{numroads: 1, roads: [100]}, rest} = IAmDispatcher.decode(data)

      assert {:ok, %IAmDispatcher{numroads: 2, roads: [200, 300]}, <<>>} =
               IAmDispatcher.decode(rest)
    end

    test "returns error for incomplete header (only type byte)" do
      data = <<0x81>>
      assert {:ok, :incomplete, ^data} = IAmDispatcher.decode(data)
    end

    test "returns error for incomplete numroads (has type but no numroads)" do
      # already tested above
      data = <<0x81>>
      assert {:ok, :incomplete, ^data} = IAmDispatcher.decode(data)
    end

    test "returns error for incomplete roads data (missing some u16s)" do
      # Wants 2 roads (4 bytes), but only provides 1 byte
      data = <<0x81, 0x02, 0x00>>
      assert {:ok, :incomplete, ^data} = IAmDispatcher.decode(data)
    end
  end

  describe "encode/1" do
    test "encodes single road [66] correctly" do
      struct = %IAmDispatcher{numroads: 1, roads: [66]}
      expected = <<0x81, 0x01, 0x00, 0x42>>
      assert IAmDispatcher.encode(struct) == expected
    end

    test "encodes multiple roads [66, 368, 5000] correctly" do
      struct = %IAmDispatcher{numroads: 3, roads: [66, 368, 5000]}
      expected = <<0x81, 0x03, 0x00, 0x42, 0x01, 0x70, 0x13, 0x88>>
      assert IAmDispatcher.encode(struct) == expected
    end

    test "encodes zero roads correctly" do
      struct = %IAmDispatcher{numroads: 0, roads: []}
      expected = <<0x81, 0x00>>
      assert IAmDispatcher.encode(struct) == expected
    end

    test "encodes [100, 200] correctly" do
      struct = %IAmDispatcher{numroads: 2, roads: [100, 200]}
      expected = <<0x81, 0x02, 0x00, 0x64, 0x00, 0xC8>>
      assert IAmDispatcher.encode(struct) == expected
    end

    test "raises RuntimeError when encoding non-struct" do
      assert_raise RuntimeError,
                   fn ->
                     IAmDispatcher.encode("not a struct")
                   end

      assert_raise RuntimeError, fn ->
        IAmDispatcher.encode(%{numroads: 1, roads: [1]})
      end
    end
  end

  describe "round-trip encode/decode" do
    test "encoding then decoding returns equivalent struct" do
      original = %IAmDispatcher{numroads: 2, roads: [100, 200]}
      encoded = IAmDispatcher.encode(original)
      assert {:ok, decoded, <<>>} = IAmDispatcher.decode(encoded)
      assert decoded.numroads == original.numroads
      assert decoded.roads == original.roads
    end

    test "decoding then encoding returns original binary" do
      # roads: [66]
      original_binary = <<0x81, 0x01, 0x00, 0x42>>

      {:ok, %IAmDispatcher{numroads: 1, roads: [66]} = decoded, <<>>} =
        IAmDispatcher.decode(original_binary)

      assert IAmDispatcher.encode(decoded) == original_binary
    end

    test "round-trip works for zero roads" do
      original = %IAmDispatcher{numroads: 0, roads: []}
      encoded = IAmDispatcher.encode(original)
      assert {:ok, %IAmDispatcher{numroads: 0, roads: []}, <<>>} = IAmDispatcher.decode(encoded)
    end
  end
end
