defmodule Protohacker.InsecureSocketLayer.MessageParserTest do
  use ExUnit.Case
  alias Protohacker.InsecureSocketLayer.MessageParser

  describe "base cases" do
    test "finds toy with maximum copies" do
      input = "10x toy car,15x dog on a string,4x inflatable motorcycle"
      assert MessageParser.find_max_toy(input) == {:ok, "15x dog on a string"}
    end

    test "single toy returns itself" do
      assert MessageParser.find_max_toy("999x rare item") == {:ok, "999x rare item"}
    end
  end

  describe "complex cases" do
    test "handles leading/trailing spaces" do
      input = " 1x a , 2x b , 3x c "
      assert MessageParser.find_max_toy(input) == {:ok, "3x c"}
    end

    test "handles tie by returning any (first max)" do
      # Spec says: "If multiple toys share the maximum number, you can break the tie arbitrarily."
      input = "5x toy A,5x toy B"
      result = MessageParser.find_max_toy(input)
      assert result == {:ok, "5x toy A"} or result == {:ok, "5x toy B"}
    end
  end
end
