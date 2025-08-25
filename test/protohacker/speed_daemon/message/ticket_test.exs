defmodule Protohacker.SpeedDaemon.Message.TicketTest do
  use ExUnit.Case

  alias Protohacker.SpeedDaemon.Message.Ticket

  describe "decode/1" do
    test "parses Ticket{plate: 'UN1X', ...} from example" do
      # Hex: 21 04 55 4e 31 58 00 42 00 64 00 01 e2 40 00 6e 00 01 e3 a8 27 10
      data = <<
        0x21,
        # plate: "UN1X"
        0x04,
        0x55,
        0x4E,
        0x31,
        0x58,
        # road: 66
        0x00,
        0x42,
        # mile1: 100
        0x00,
        0x64,
        # timestamp1: 123456
        0x00,
        0x01,
        0xE2,
        0x40,
        # mile2: 110
        0x00,
        0x6E,
        # timestamp2: 123816
        0x00,
        0x01,
        0xE3,
        0xA8,
        # speed: 10000
        0x27,
        0x10
      >>

      assert {:ok, ticket, <<>>} = Ticket.decode(data)

      assert %Ticket{
               plate: "UN1X",
               road: 66,
               mile1: 100,
               timestamp1: 123_456,
               mile2: 110,
               timestamp2: 123_816,
               speed: 10_000
             } = ticket
    end

    test "parses Ticket{plate: 'RE05BKG', ...} from example" do
      # Hex: 21 07 52 45 30 35 42 4b 47 01 70 04 d2 00 0f 42 40 04 d3 00 0f 42 7c 17 70
      data = <<
        0x21,
        # plate: "RE05BKG"
        0x07,
        0x52,
        0x45,
        0x30,
        0x35,
        0x42,
        0x4B,
        0x47,
        # road: 368
        0x01,
        0x70,
        # mile1: 1234
        0x04,
        0xD2,
        # timestamp1: 1000000
        0x00,
        0x0F,
        0x42,
        0x40,
        # mile2: 1235
        0x04,
        0xD3,
        # timestamp2: 1000060
        0x00,
        0x0F,
        0x42,
        0x7C,
        # speed: 6000
        0x17,
        0x70
      >>

      assert {:ok, ticket, <<>>} = Ticket.decode(data)

      assert %Ticket{
               plate: "RE05BKG",
               road: 368,
               mile1: 1234,
               timestamp1: 1_000_000,
               mile2: 1235,
               timestamp2: 1_000_060,
               speed: 6000
             } = ticket
    end

    test "handles concatenated messages" do
      # Two Ticket messages
      data = <<
        # First: Ticket{"A", road: 1, ...}
        0x21,
        0x01,
        0x41,
        0x00,
        0x01,
        0x00,
        0x02,
        0x00,
        0x00,
        0x00,
        0x0A,
        0x00,
        0x03,
        0x00,
        0x00,
        0x00,
        0x14,
        0x00,
        0x04,
        # Second: Ticket{"B", road: 2, ...}
        0x21,
        0x01,
        0x42,
        0x00,
        0x02,
        0x00,
        0x04,
        0x00,
        0x00,
        0x00,
        0x1E,
        0x00,
        0x05,
        0x00,
        0x00,
        0x00,
        0x28,
        0x00,
        0x06
      >>

      assert {:ok, %Ticket{plate: "A", road: 1, speed: 4}, rest} = Ticket.decode(data)
      assert {:ok, %Ticket{plate: "B", road: 2, speed: 6}, <<>>} = Ticket.decode(rest)
    end

    test "returns error for incomplete header (only type byte)" do
      data = <<0x21>>
      assert {:error, :invalid_ticket_format, ^data} = Ticket.decode(data)
    end

    test "returns error for incomplete plate length (missing string)" do
      # has length, no string
      data = <<0x21, 0x03>>
      assert {:error, :invalid_ticket_format, ^data} = Ticket.decode(data)
    end

    test "returns error for incomplete plate string" do
      # wants 4 chars, got 2
      data = <<0x21, 0x04, 0x41, 0x42>>
      assert {:error, :invalid_ticket_format, ^data} = Ticket.decode(data)
    end

    test "returns error for incomplete body (after plate)" do
      # Has plate "X", but not enough for road (2 bytes) and rest
      # only 1 byte of road
      data = <<0x21, 0x01, 0x58, 0x00>>
      assert {:error, :invalid_ticket_format, ^data} = Ticket.decode(data)
    end

    test "returns error for wrong message type" do
      # Error{"bad"}
      data = <<0x10, 0x03, 0x62, 0x61, 0x64>>
      assert {:error, :unknown_format, ^data} = Ticket.decode(data)
    end

    test "returns error for empty binary" do
      assert {:error, :unknown_format, <<>>} = Ticket.decode(<<>>)
    end
  end

  describe "error handling on invalid plate string" do
    test "returns :invalid_value if string contains invalid UTF-8 (but still binary)" do
      # Valid binary, but not valid string
      data = <<
        # plate: <<255,255>>
        0x21,
        0x02,
        0xFF,
        0xFF,
        # road: 1
        0x00,
        0x01,
        # mile1: 2
        0x00,
        0x02,
        # timestamp1: 3
        0x00,
        0x00,
        0x00,
        0x03,
        # mile2: 4
        0x00,
        0x04,
        # timestamp2: 5
        0x00,
        0x00,
        0x00,
        0x05,
        # speed: 6
        0x00,
        0x06
      >>

      assert {:error, :invalid_ascii, %{plate: <<0xFF, 0xFF>>}} = Ticket.decode(data)
    end
  end

  # Optional: Add encode/1 later, but test structure now
  # describe "encode/1" do
  #   # Add when you implement encoding
  # end

  describe "round-trip" do
    test "decoding a valid binary and expecting correct struct" do
      data = <<
        # plate: "FOO"
        0x21,
        0x03,
        0x46,
        0x4F,
        0x4F,
        # road: 1
        0x00,
        0x01,
        # mile1: 10
        0x00,
        0x0A,
        # timestamp1: 16
        0x00,
        0x00,
        0x00,
        0x10,
        # mile2: 20
        0x00,
        0x14,
        # timestamp2: 32
        0x00,
        0x00,
        0x00,
        0x20,
        # speed: 8
        0x00,
        0x08
      >>

      assert {:ok, %Ticket{plate: "FOO", road: 1, speed: 8}, <<>>} = Ticket.decode(data)
    end
  end
end
