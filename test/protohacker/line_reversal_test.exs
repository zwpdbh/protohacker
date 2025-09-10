defmodule Protohacker.LineReversalTest do
  use ExUnit.Case
  alias Protohacker.LineReversal.LRCP.Protocol
  @max_int 2_147_483_648

  describe "Protocol test" do
    test "invalid packets" do
      assert Protocol.parse_packet("") == :error
      assert Protocol.parse_packet("/") == :error
      assert Protocol.parse_packet("//") == :error
      assert Protocol.parse_packet("/connect") == :error
      assert Protocol.parse_packet("/connect/1") == :error
      assert Protocol.parse_packet("connect/1/") == :error
    end

    test "returns an error for integers that are too large" do
      assert Protocol.parse_packet("/connect/#{@max_int}/") == :error
      assert Protocol.parse_packet("/ack/#{@max_int}/1/") == :error
      assert Protocol.parse_packet("/ack/1/#{@max_int}/") == :error
    end

    test "connect packet" do
      assert Protocol.parse_packet("/connect/231/") == {:ok, {:connect, 231}}
    end

    test "close packet" do
      assert Protocol.parse_packet("/close/231/") == {:ok, {:close, 231}}
    end

    test "ack packet" do
      assert Protocol.parse_packet("/ack/123/456/") == {:ok, {:ack, 123, 456}}
    end

    test "data packet" do
      assert Protocol.parse_packet("/data/123/456/hello\\/world\\\\!\n/") ==
               {:ok, {:data, 123, 456, "hello\\/world\\\\!\n"}}
    end
  end
end
