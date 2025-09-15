defmodule Protohacker.InsecureSocketLayer.CipherTest do
  use ExUnit.Case
  alias Protohacker.InsecureSocketLayer.Cipher
  import Bitwise

  describe "cipher reversebits" do
    test "reversebits reverses bits in each byte correctly" do
      # Single byte: 0b11000001 -> 0b10000011
      assert Cipher.reversebits(<<0b11000001>>) == <<0b10000011>>

      # All bits flipped pattern: 0b10101010 -> 0b01010101
      assert Cipher.reversebits(<<0b10101010>>) == <<0b01010101>>

      # Boundary: 0b00000000 -> 0b00000000
      assert Cipher.reversebits(<<0>>) == <<0>>

      # Boundary: 0b11111111 -> 0b11111111 (palindrome)
      assert Cipher.reversebits(<<0b11111111>>) == <<0b11111111>>

      # Multiple bytes
      assert Cipher.reversebits(<<0b11110000, 0b10100101>>) == <<0b00001111, 0b10100101>>

      # Empty binary
      assert Cipher.reversebits(<<>>) == <<>>

      # ASCII example: 'A' = 65 = 0b01000001 -> reversed = 0b10000010 = 130
      assert Cipher.reversebits(<<65>>) == <<130>>
    end

    test "reversebits is its own inverse for any byte" do
      # Reversing twice should return original
      for byte <- 0..255 do
        original = <<byte>>
        reversed_once = Cipher.reversebits(original)
        reversed_twice = Cipher.reversebits(reversed_once)

        assert reversed_twice == original,
               "Failed for byte #{byte}: #{inspect(reversed_twice)} != #{inspect(original)}"
      end
    end
  end

  describe "cipher xor_n bits" do
    test "xor_n XORs each byte with n correctly" do
      # Example from spec: "68 65 6c 6c 6f" with n=1 -> "69 64 6d 6d 6e"
      input = <<0x68, 0x65, 0x6C, 0x6C, 0x6F>>
      expected = <<0x69, 0x64, 0x6D, 0x6D, 0x6E>>
      assert Cipher.xor_n(input, 1) == expected

      # XOR with 0 should be identity
      assert Cipher.xor_n(<<1, 2, 3>>, 0) == <<1, 2, 3>>

      # XOR with 255 flips all bits
      assert Cipher.xor_n(<<0x00, 0xFF, 0xAA>>, 0xFF) == <<0xFF, 0x00, 0x55>>

      # Empty binary
      assert Cipher.xor_n(<<>>, 42) == <<>>

      # Single byte edge cases
      assert Cipher.xor_n(<<0>>, 0xFF) == <<0xFF>>
      assert Cipher.xor_n(<<0xFF>>, 0xFF) == <<0>>
    end

    test "xor_n is its own inverse when applied twice with same n" do
      original = <<1, 2, 3, 4, 5, 255, 0, 128>>
      n = 173

      once = Cipher.xor_n(original, n)
      twice = Cipher.xor_n(once, n)

      assert twice == original
    end

    test "xor_n with n outside 0-255 raises FunctionClauseError" do
      assert_raise FunctionClauseError, fn ->
        Cipher.xor_n(<<1, 2, 3>>, 256)
      end

      assert_raise FunctionClauseError, fn ->
        Cipher.xor_n(<<1, 2, 3>>, -1)
      end
    end
  end

  describe "cipher xor_pos" do
    test "xor_pos XORs each byte by its position index starting from 0" do
      # Example: <<0x68, 0x65, 0x6C>> at positions 0,1,2
      # 0x68 XOR 0 = 0x68
      # 0x65 XOR 1 = 0x64
      # 0x6C XOR 2 = 0x6E
      # "hel"
      input = <<0x68, 0x65, 0x6C>>
      # "hdn"
      expected = <<0x68, 0x64, 0x6E>>
      assert Cipher.xor_pos(input) == expected

      # Empty binary
      assert Cipher.xor_pos(<<>>) == <<>>

      # Single byte at index 0
      assert Cipher.xor_pos(<<0xFF>>) == <<0xFF>>

      # Two bytes: <<10, 10>> → 10^0=10, 10^1=11
      assert Cipher.xor_pos(<<10, 10>>) == <<10, 11>>

      # Longer example
      input = <<1, 2, 3, 4, 5>>
      expected = <<bxor(1, 0), bxor(2, 1), bxor(3, 2), bxor(4, 3), bxor(5, 4)>>
      assert Cipher.xor_pos(input) == expected
    end

    test "xor_pos with long binary doesn't break on index > 255" do
      # Index can be > 255 — but XOR is still safe because bxor works on integers
      # and only the least significant 8 bits matter for byte output
      # 300 zero bytes
      data = :binary.copy(<<0>>, 300)
      result = Cipher.xor_pos(data)

      # Check byte at position 256: 0 XOR 256 = 256 → but stored as a byte → 256 &&& 0xFF = 0
      # Actually, bxor(0, 256) = 256, but <<256>> is <<0>> because it wraps to 8 bits!
      # Wait — this is critical!

      # In Elixir, <<256>> is equivalent to <<0>> because it truncates to 8 bits.
      # So we must ensure we're only outputting 8-bit bytes.

      # Let's check position 256
      byte_at_256 = :binary.at(result, 256)
      # Explicitly mask to 8 bits
      assert <<byte_at_256>> == <<bxor(0, 256)>>

      # But in our implementation, `bxor(byte, index)` may return >255, but when wrapped in <<>>,
      # Elixir automatically truncates to 8 bits — which is what we want!

      # Let's test explicitly:
      assert <<bxor(0, 256)>> == <<0>>
      assert <<bxor(0, 257)>> == <<1>>
      assert <<bxor(0, 511)>> == <<255>>
    end
  end

  describe "cipher add_n" do
    test "add_n adds n to each byte modulo 256" do
      # Basic: add 1 to <<0, 1, 255>>
      assert Cipher.add_n(<<0, 1, 255>>, 1) == <<1, 2, 0>>

      # Add 0 → identity
      assert Cipher.add_n(<<10, 20, 30>>, 0) == <<10, 20, 30>>

      # Add 256 → same as adding 0 (modulo 256)
      assert Cipher.add_n(<<100, 200, 255>>, 256) == <<100, 200, 255>>

      # Add 2 to 254, 255 → 0, 1
      assert Cipher.add_n(<<254, 255>>, 2) == <<0, 1>>

      # Add 10 to <<250, 251>> → 4, 5 (wrapped)
      expected = <<rem(250 + 10, 256), rem(251 + 10, 256)>>
      assert Cipher.add_n(<<250, 251>>, 10) == expected

      # Empty binary
      assert Cipher.add_n(<<>>, 5) == <<>>

      # ASCII example: "abc" + 1 = "bcd"
      assert Cipher.add_n("abc", 1) == "bcd"
    end

    test "add_n wraps correctly for large additions within allowed n" do
      # 50 + 255 = 305 → 305 mod 256 = 49
      assert Cipher.add_n(<<50>>, 255) == <<rem(50 + 255, 256)>>
      assert Cipher.add_n(<<50>>, 255) == <<49>>

      # 10 + 256 = 266 → 266 mod 256 = 10
      assert Cipher.add_n(<<10>>, 256) == <<10>>
    end

    test "add_n with n outside [0,256] raises FunctionClauseError" do
      assert_raise FunctionClauseError, fn ->
        Cipher.add_n(<<1, 2, 3>>, -1)
      end

      assert_raise FunctionClauseError, fn ->
        Cipher.add_n(<<1, 2, 3>>, 257)
      end
    end
  end

  describe "cipher add_pos" do
    test "add_pos adds position index to each byte modulo 256" do
      # Example: <<100, 200, 255>> at positions 0,1,2
      # 100+0=100, 200+1=201, 255+2=257 → 257 rem 256 = 1
      input = <<100, 200, 255>>
      expected = <<100, 201, 1>>
      assert Cipher.add_pos(input) == expected

      # Empty binary
      assert Cipher.add_pos(<<>>) == <<>>

      # Single byte at index 0 → unchanged
      assert Cipher.add_pos(<<50>>) == <<50>>

      # Two bytes: <<255, 255>> → 255+0=255, 255+1=0
      assert Cipher.add_pos(<<255, 255>>) == <<255, 0>>

      # ASCII example: "aaa" → ?a=97
      # positions: 0,1,2 → 97+0=97=?a, 97+1=98=?b, 97+2=99=?c → "abc"
      assert Cipher.add_pos("aaa") == "abc"

      # Wrap example: <<254, 254, 254>> at positions 0,1,2
      # 254+0=254, 254+1=255, 254+2=256→0
      assert Cipher.add_pos(<<254, 254, 254>>) == <<254, 255, 0>>
    end

    test "add_pos handles large indices (index > 255) correctly" do
      # Create binary with 300 bytes of <<0>>
      data = :binary.copy(<<0>>, 300)
      result = Cipher.add_pos(data)

      # At position 256: 0 + 256 = 256 → rem(256, 256) = 0
      byte_at_256 = :binary.at(result, 256)
      assert byte_at_256 == rem(0 + 256, 256)

      # At position 257: 0 + 257 = 257 → rem(257, 256) = 1
      byte_at_257 = :binary.at(result, 257)
      assert byte_at_257 == rem(0 + 257, 256)

      # At position 511: 0 + 511 = 511 → rem(511, 256) = 255
      # But we only have 300 bytes, so check position 299 instead
      byte_at_299 = :binary.at(result, 299)
      # 299 % 256 = 43
      assert byte_at_299 == rem(0 + 299, 256)
      assert byte_at_299 == 43
    end
  end

  describe "cipher spec parsing" do
    test "parses empty cipher spec (just 00)" do
      assert Cipher.parse_cipher_spec(<<0x00>>) == {:ok, <<>>, []}
    end

    test "parses single reversebits operation" do
      assert Cipher.parse_cipher_spec(<<0x01, 0x00>>) == {:ok, <<>>, [{:reversebits}]}
    end

    test "parses xor_n with operand" do
      assert Cipher.parse_cipher_spec(<<0x02, 0xAB, 0x00>>) == {:ok, <<>>, [{:xor_n, 0xAB}]}
    end

    test "parses xor_pos" do
      assert Cipher.parse_cipher_spec(<<0x03, 0x00>>) == {:ok, <<>>, [{:xor_pos}]}
    end

    test "parses add_n with operand" do
      assert Cipher.parse_cipher_spec(<<0x04, 0x10, 0x00>>) == {:ok, <<>>, [{:add_n, 0x10}]}
    end

    test "parses add_pos" do
      assert Cipher.parse_cipher_spec(<<0x05, 0x00>>) == {:ok, <<>>, [{:add_pos}]}
    end

    test "parses multiple operations in sequence" do
      # xor(1), reversebits → 02 01 01 00
      spec = <<0x02, 0x01, 0x01, 0x00>>
      assert Cipher.parse_cipher_spec(spec) == {:ok, <<>>, [{:xor_n, 0x01}, {:reversebits}]}

      # addpos, addpos → 05 05 00
      spec = <<0x05, 0x05, 0x00>>
      assert Cipher.parse_cipher_spec(spec) == {:ok, <<>>, [{:add_pos}, {:add_pos}]}
    end

    test "returns remaining binary after 00" do
      # Cipher spec + extra data
      input = <<0x01, 0x00, "hello">>
      assert Cipher.parse_cipher_spec(input) == {:ok, "hello", [{:reversebits}]}
    end

    test "returns error on invalid opcode" do
      # Unknown opcode 0x06
      input = <<0x06, 0x00>>
      assert Cipher.parse_cipher_spec(input) == {:error, <<0x06, 0x00>>, []}

      # Unknown opcode in middle
      input = <<0x01, 0x06, 0x00>>
      assert Cipher.parse_cipher_spec(input) == {:error, <<0x06, 0x00>>, [{:reversebits}]}
    end

    test "returns error on incomplete spec (no 00)" do
      input = <<0x01, 0x02, 0xAB>>
      assert Cipher.parse_cipher_spec(input) == {:error, "", [{:xor_n, 171}, {:reversebits}]}
    end

    test "parses longer valid spec with trailing data" do
      # xor(255), add(10), reversebits, xorpos, 00 + "TRAIL"
      input = <<0x02, 0xFF, 0x04, 0x0A, 0x01, 0x03, 0x00, "TRAIL">>

      expected_ops = [
        {:xor_n, 0xFF},
        {:add_n, 0x0A},
        {:reversebits},
        {:xor_pos}
      ]

      assert Cipher.parse_cipher_spec(input) == {:ok, "TRAIL", expected_ops}
    end
  end

  describe "no_op_ciphers? (complete version)" do
    test "empty cipher is no-op" do
      assert Cipher.no_op_ciphers?([]) == true
    end

    test "xor_n(0) is no-op" do
      assert Cipher.no_op_ciphers?([{:xor_n, 0}]) == true
    end

    test "xor_n(x), xor_n(x) is no-op" do
      assert Cipher.no_op_ciphers?([{:xor_n, 5}, {:xor_n, 5}]) == true
    end

    test "reversebits, reversebits is no-op" do
      assert Cipher.no_op_ciphers?([{:reversebits}, {:reversebits}]) == true
    end

    test "complex no-op: xor_n(1), xor_n(5), xor_n(5), xor_n(1)" do
      assert Cipher.no_op_ciphers?([
               {:xor_n, 1},
               {:xor_n, 5},
               {:xor_n, 5},
               {:xor_n, 1}
             ]) == true
    end

    test "mixed no-op: reversebits, xor_n(0), reversebits" do
      assert Cipher.no_op_ciphers?([
               {:reversebits},
               {:xor_n, 0},
               {:reversebits}
             ]) == true
    end

    test "non no-op returns false" do
      assert Cipher.no_op_ciphers?([{:xor_n, 1}]) == false
      assert Cipher.no_op_ciphers?([{:add_n, 1}]) == false
    end

    test "any cipher with xor_pos or add_pos returns false" do
      assert Cipher.no_op_ciphers?([{:xor_pos}]) == false
      assert Cipher.no_op_ciphers?([{:add_pos}]) == false
      assert Cipher.no_op_ciphers?([{:xor_n, 0}, {:xor_pos}]) == false
    end

    test "add_n(x), add_n(y) with x+y ≡ 0 mod 256 is no-op" do
      assert Cipher.no_op_ciphers?([{:add_n, 200}, {:add_n, 56}]) == true
    end
  end
end
