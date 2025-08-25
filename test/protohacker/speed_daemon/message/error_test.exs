defmodule Protohacker.SpeedDaemon.Message.ErrorTest do
  use ExUnit.Case
  alias Protohacker.SpeedDaemon.Message.Error

  describe "decode/1" do
    test "parses Error{msg: 'bad'} from example" do
      # Hex: 10 03 62 61 64
      data = <<0x10, 0x03, 0x62, 0x61, 0x64>>
      assert {:ok, %Error{msg: "bad"}, <<>>} = Error.decode(data)
    end

    test "parses Error{msg: 'illegal msg'} from example" do
      # Hex: 10 0b 69 6c 6c 65 67 61 6c 20 6d 73 67
      data = <<0x10, 0x0B, 0x69, 0x6C, 0x6C, 0x65, 0x67, 0x61, 0x6C, 0x20, 0x6D, 0x73, 0x67>>
      assert {:ok, %Error{msg: "illegal msg"}, <<>>} = Error.decode(data)
    end

    test "parses empty string message" do
      # Error{""}: 10 00
      data = <<0x10, 0x00>>
      assert {:ok, %Error{msg: ""}, <<>>} = Error.decode(data)
    end

    test "handles concatenated messages" do
      # Two messages: Error{"hi"}, Error{"ok"}
      data = <<0x10, 0x02, 0x68, 0x69, 0x10, 0x02, 0x6F, 0x6B>>

      assert {:ok, %Error{msg: "hi"}, rest} = Error.decode(data)
      assert {:ok, %Error{msg: "ok"}, <<>>} = Error.decode(rest)
    end

    test "returns error for incomplete string data" do
      # Length says 5, but only 2 bytes provided
      data = <<0x10, 0x05, 0x68, 0x69>>

      # This fails in the second clause: not enough data for `binary-size(5)`
      assert {:error, :incomplete, ^data} = Error.decode(data)
    end

    test "returns error for incomplete header (missing length)" do
      # Only type byte
      data = <<0x10>>
      assert {:error, :incomplete, ^data} = Error.decode(data)
    end

    test "returns error for incomplete header (has length but no string)" do
      # Has length 3, but no string bytes
      data = <<0x10, 0x03>>
      assert {:error, :incomplete, ^data} = Error.decode(data)
    end

    test "returns error for wrong message type" do
      # Starts with 0x20 (Plate), not 0x10
      data = <<0x20, 0x03, 0x66, 0x6F, 0x6F>>
      assert {:error, :invalid_type, ^data} = Error.decode(data)
    end

    test "returns error for empty binary" do
      assert {:error, :invalid_type, <<>>} = Error.decode(<<>>)
    end
  end

  describe "encode/1" do
    test "encodes Error{msg: 'bad'} correctly" do
      # 10 03 62 61 64
      expected = <<0x10, 0x03, 0x62, 0x61, 0x64>>
      assert Error.encode("bad") == expected
    end

    test "encodes Error{msg: 'illegal msg'} correctly" do
      expected = <<0x10, 0x0B, 0x69, 0x6C, 0x6C, 0x65, 0x67, 0x61, 0x6C, 0x20, 0x6D, 0x73, 0x67>>
      assert Error.encode("illegal msg") == expected
    end

    test "encodes empty string correctly" do
      expected = <<0x10, 0x00>>
      assert Error.encode("") == expected
    end

    test "raises if msg is not binary" do
      assert_raise FunctionClauseError, fn ->
        Error.encode(:bad)
      end

      assert_raise FunctionClauseError, fn ->
        Error.encode(123)
      end
    end
  end

  describe "round-trip encode/decode" do
    test "encoding then decoding returns original message" do
      msg = "test error message"
      encoded = Error.encode(msg)
      assert {:ok, %Error{msg: ^msg}, <<>>} = Error.decode(encoded)
    end

    test "decoding then encoding returns original binary" do
      # Error{"hello"}
      original = <<0x10, 0x05, 0x68, 0x65, 0x6C, 0x6C, 0x6F>>
      assert {:ok, %Error{msg: "hello"}, <<>>} = Error.decode(original)
      assert Error.encode("hello") == original
    end
  end
end
