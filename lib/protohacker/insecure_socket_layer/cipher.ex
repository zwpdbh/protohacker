defmodule Protohacker.InsecureSocketLayer.Cipher do
  # Reverse the order of bits in the byte, so the least-significant bit becomes
  # the most-significant bit, the 2nd-least-significant becomes the 2nd-most-significant, and so on.
  def reversebits(data) when is_binary(data) do
    for <<byte <- data>>, into: <<>> do
      <<b7::1, b6::1, b5::1, b4::1, b3::1, b2::1, b1::1, b0::1>> = <<byte>>
      <<b0::1, b1::1, b2::1, b3::1, b4::1, b5::1, b6::1, b7::1>>
    end
  end

  # XOR means "eXclusive OR".
  # A XOR B XOR B == A is why XOR is used in encryption, checksums, and data toggling.
  # XOR the byte by the value N. Note that 0 is a valid value for N.
  # 0 is a valid value for n.
  # For example, if n is 1, then input hex "68 65 6c 6c 6f"
  # becomes "69 64 6d 6d 6e"
  def xor_n(data, n) when is_binary(data) and is_integer(n) and n >= 0 and n <= 255 do
    for <<byte <- data>>, into: <<>> do
      <<Bitwise.bxor(byte, n)>>
    end
  end

  # XOR the byte by its position in the stream, starting from 0.
  def xor_pos(data, start_pos \\ 0) when is_binary(data) do
    xor_pos(data, start_pos, _index = 0, _acc = <<>>)
  end

  defp xor_pos(<<>>, _start_pos, _index, acc), do: acc

  defp xor_pos(<<byte, rest::binary>>, start_pos, index, acc) do
    new_byte = Bitwise.bxor(byte, start_pos + index)
    xor_pos(rest, start_pos, index + 1, <<acc::binary, new_byte>>)
  end

  # Add N to the byte, modulo 256. Note that 0 is a valid value for N, and addition wraps, so that 255+1=0, 255+2=1, and so on.
  def add_n(data, n) when is_binary(data) and is_integer(n) and n >= 0 and n <= 256 do
    for <<byte <- data>>, into: <<>> do
      # Use `rem` to compute (byte + n) mod 256
      # Since byte + n is non-negative, `rem` behaves like mathematical modulo
      result = rem(byte + n, 256)
      <<result>>
    end
  end

  # Add the position in the stream to the byte, modulo 256,
  # starting from 0. Addition wraps, so that 255+1=0, 255+2=1, and so on.
  def add_pos(data, start_pos \\ 0) when is_binary(data) do
    data
    |> :binary.bin_to_list()
    |> Enum.with_index()
    |> Enum.map(fn {byte, index} -> rem(byte + start_pos + index, 256) end)
    |> :binary.list_to_bin()
  end

  # Add subtract_pos for decoding add_pos operations
  def subtract_pos(data, start_pos \\ 0)
      when is_binary(data) and is_integer(start_pos) and start_pos >= 0 do
    data
    |> :binary.bin_to_list()
    |> Enum.with_index()
    |> Enum.map(fn {byte, index} -> rem(byte - (start_pos + index) + 256, 256) end)
    |> :binary.list_to_bin()
  end

  # parse cipher specs
  def parse_cipher_spec(binary) do
    parse_cipher_spec_aux(binary, _acc = [])
  end

  # means reach the end of cipher spec
  defp parse_cipher_spec_aux(<<0x00, rest::binary>>, acc) do
    {:ok, rest, acc |> Enum.reverse()}
  end

  defp parse_cipher_spec_aux(<<0x01, rest::binary>>, acc) do
    parse_cipher_spec_aux(rest, [{:reversebits}] ++ acc)
  end

  defp parse_cipher_spec_aux(<<0x02, n, rest::binary>>, acc) do
    parse_cipher_spec_aux(rest, [{:xor_n, n}] ++ acc)
  end

  defp parse_cipher_spec_aux(<<0x03, rest::binary>>, acc) do
    parse_cipher_spec_aux(rest, [{:xor_pos}] ++ acc)
  end

  defp parse_cipher_spec_aux(<<0x04, n, rest::binary>>, acc) do
    parse_cipher_spec_aux(rest, [{:add_n, n}] ++ acc)
  end

  defp parse_cipher_spec_aux(<<0x05, rest::binary>>, acc) do
    parse_cipher_spec_aux(rest, [{:add_pos}] ++ acc)
  end

  defp parse_cipher_spec_aux(binary, acc) do
    {:error, binary, acc}
  end

  # Returns true if cipher leaves EVERY byte unchanged → must reject.
  def no_op_ciphers?(ciphers) when is_list(ciphers) do
    # If any op is position-dependent, it's NOT a pure no-op → safe
    if Enum.any?(ciphers, &(match?({:xor_pos}, &1) or match?({:add_pos}, &1))) do
      false
    else
      # Create binary with all 256 bytes: 0, 1, 2, ..., 255
      input = for b <- 0..255, into: <<>>, do: <<b>>

      # Apply cipher to entire binary
      output = apply_cipher(input, ciphers)

      # If unchanged → no-op
      input == output
    end
  end

  # Apply a list of ciphers to a binary
  def apply_cipher(data, operations, start_pos \\ 0)
      when is_binary(data) and is_integer(start_pos) do
    Enum.reduce(operations, {data, start_pos}, fn
      {:reversebits}, {acc, pos} -> {reversebits(acc), pos}
      {:xor_n, n}, {acc, pos} -> {xor_n(acc, n), pos}
      {:xor_pos}, {acc, pos} -> {xor_pos(acc, pos), pos + byte_size(acc)}
      {:add_n, n}, {acc, pos} -> {add_n(acc, n), pos}
      {:add_pos}, {acc, pos} -> {add_pos(acc, pos), pos + byte_size(acc)}
    end)
  end

  # The server must apply the inverse of the cipher spec to decode the request stream.
  def decode_message(message, ciphers, start_pos) do
    message
    |> apply_cipher(ciphers |> Enum.reverse(), start_pos)
  end

  def encode_message(message, ciphers, start_pos) do
    message
    |> apply_cipher(ciphers, start_pos)
  end
end
