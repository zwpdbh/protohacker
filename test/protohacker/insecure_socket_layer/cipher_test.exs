defmodule Protohacker.InsecureSocketLayer.CipherTest do
  use ExUnit.Case
  alias Protohacker.InsecureSocketLayer.Cipher
  import Bitwise

  describe "no_op_ciphers?/1" do
    test "empty cipher spec is no-op" do
      assert Cipher.no_op_ciphers?([]) == true
    end

    test "xor(0) is no-op" do
      assert Cipher.no_op_ciphers?([{:xor, 0}]) == true
    end

    test "xor(X), xor(X) cancels out" do
      assert Cipher.no_op_ciphers?([{:xor, 123}, {:xor, 123}]) == true
      assert Cipher.no_op_ciphers?([{:xor, 0xAB}, {:xor, 0xAB}]) == true
    end

    test "reversebits, reversebits cancels out" do
      assert Cipher.no_op_ciphers?([:reversebits, :reversebits]) == true

      assert Cipher.no_op_ciphers?([:reversebits, :reversebits, :reversebits, :reversebits]) ==
               true
    end

    test "xor(A), xor(B), xor(C) where A xor B = C" do
      # 0xA0 xor 0x0B = 0xAB
      assert Cipher.no_op_ciphers?([{:xor, 0xA0}, {:xor, 0x0B}, {:xor, 0xAB}]) == true

      # 0x55 xor 0x55 = 0x00
      assert Cipher.no_op_ciphers?([{:xor, 0x55}, {:xor, 0x55}, {:xor, 0x00}]) == true
    end

    test "mixed operations that cancel out" do
      # xor(0) + reversebits + reversebits = no-op
      assert Cipher.no_op_ciphers?([{:xor, 0}, :reversebits, :reversebits]) == true

      # add(0) + reversebits + reversebits = no-op
      assert Cipher.no_op_ciphers?([{:add, 0}, :reversebits, :reversebits]) == true
    end

    test "non-no-op ciphers" do
      # Single xor with non-zero value
      assert Cipher.no_op_ciphers?([{:xor, 1}]) == false

      # Single reversebits
      assert Cipher.no_op_ciphers?([:reversebits]) == false

      # xor with different values that don't cancel
      assert Cipher.no_op_ciphers?([{:xor, 1}, {:xor, 2}]) == false

      # add non-zero value
      assert Cipher.no_op_ciphers?([{:add, 1}]) == false

      # sub non-zero value
      assert Cipher.no_op_ciphers?([{:sub, 1}]) == false

      # xorpos is never no-op (position-dependent)
      assert Cipher.no_op_ciphers?([:xorpos]) == false

      # addpos is never no-op (position-dependent)
      assert Cipher.no_op_ciphers?([:addpos]) == false

      # subpos is never no-op (position-dependent)
      assert Cipher.no_op_ciphers?([:subpos]) == false
    end

    test "complex combinations" do
      # Multiple pairs of reversebits cancel out
      assert Cipher.no_op_ciphers?([
               :reversebits,
               :reversebits,
               :reversebits,
               :reversebits
             ]) == true

      # XOR operations combine properly
      a = 0x12
      b = 0x34
      c = bxor(a, b)
      assert Cipher.no_op_ciphers?([{:xor, a}, {:xor, b}, {:xor, c}]) == true

      # Mixed operations - should not be no-op if any position-dependent ops
      assert Cipher.no_op_ciphers?([{:xor, 0}, :xorpos]) == false
    end
  end

  describe "apply/3" do
    test "empty cipher does not change data" do
      data = <<1, 2, 3, 4>>
      assert Cipher.apply(data, []) == data
    end

    test "xor(0) does not change data" do
      data = <<1, 2, 3, 4>>
      assert Cipher.apply(data, [{:xor, 0}]) == data
    end

    test "reversebits applied twice returns original" do
      data = <<0b10101010>>
      result = Cipher.apply(data, [:reversebits, :reversebits])
      assert result == data
    end

    test "xor with same value twice returns original" do
      data = <<0x42, 0xFF, 0x00>>
      key = 0xAA
      result = Cipher.apply(data, [{:xor, key}, {:xor, key}])
      assert result == data
    end
  end

  describe "reversebits/1" do
    test "reverses bits correctly" do
      # 0b10000000 (128) -> 0b00000001 (1)
      assert Cipher.reversebits(128) == 1

      # 0b00000001 (1) -> 0b10000000 (128)
      assert Cipher.reversebits(1) == 128

      # 0b10101010 (170) -> 0b01010101 (85)
      assert Cipher.reversebits(170) == 85

      # 0b01010101 (85) -> 0b10101010 (170)
      assert Cipher.reversebits(85) == 170
    end

    test "reversebits applied twice returns original" do
      for i <- 0..255 do
        reversed = Cipher.reversebits(i)
        double_reversed = Cipher.reversebits(reversed)
        assert double_reversed == i, "Failed for #{i}"
      end
    end
  end

  describe "parse_cipher_spec/1" do
    test "parses empty spec" do
      assert Cipher.parse_cipher_spec(<<0x00>>) == {:ok, [], <<>>}
    end

    test "parses reversebits" do
      assert Cipher.parse_cipher_spec(<<0x01, 0x00>>) == {:ok, [:reversebits], <<>>}
    end

    test "parses xor with value" do
      assert Cipher.parse_cipher_spec(<<0x02, 0xFF, 0x00>>) == {:ok, [{:xor, 255}], <<>>}
    end

    test "parses xorpos" do
      assert Cipher.parse_cipher_spec(<<0x03, 0x00>>) == {:ok, [:xorpos], <<>>}
    end

    test "parses add with value" do
      assert Cipher.parse_cipher_spec(<<0x04, 0x7F, 0x00>>) == {:ok, [{:add, 127}], <<>>}
    end

    test "parses addpos" do
      assert Cipher.parse_cipher_spec(<<0x05, 0x00>>) == {:ok, [:addpos], <<>>}
    end

    test "returns error for invalid spec" do
      assert Cipher.parse_cipher_spec(<<0xFF>>) == :error
    end

    test "parses complex spec" do
      binary = <<0x01, 0x02, 0xAB, 0x03, 0x00>>
      expected = {:ok, [:reversebits, {:xor, 171}, :xorpos], <<>>}
      assert Cipher.parse_cipher_spec(binary) == expected
    end
  end
end
