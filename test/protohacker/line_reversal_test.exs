defmodule Protohacker.LineReversalTest do
  use ExUnit.Case
  alias Protohacker.LineReversal.Message

  describe "Message Decode" do
    test "Contact Decode" do
      connect_packet = "/connect/1234567/"
      {:ok, connect} = Message.decode(connect_packet)

      assert connect == %Message.Connect{session: 1_234_567}
    end
  end
end
