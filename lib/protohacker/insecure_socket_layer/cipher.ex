# Lesson learned:
# Instead of: Multiple functions that operate on entire binaries
# It is better to create one interface function to process binary in which
# we use Enum.reduce to apply serveral functions operate on single byte.
# Ask: "How can I compose simple functions?" rather than "What steps do I need?"
# Ask: "How to handle data in stream processing instead of bulk processing?"

defmodule Protohacker.InsecureSocketLayer.Cipher do
  @type cipher() ::
          :reversebits
          | {:xor, byte()}
          | :xorpos
          | {:add, byte()}
          | :addpos
          | {:sub, byte()}
          | :subpos

  @type ciphers() :: [cipher()]

  @spec apply(binary(), ciphers(), non_neg_integer()) :: binary()
  def apply(data, ciphers, start_position \\ 0) when is_binary(data) do
    {encoded, _postion} =
      for <<byte <- data>>, reduce: {_acc = <<>>, start_position} do
        {acc, position} ->
          encoded =
            Enum.reduce(ciphers, byte, &apply_operation(&1, &2, position))

          {<<acc::binary, encoded>>, position + 1}
      end

    encoded
  end

  # apply one cipher on one byte
  @spec apply_operation(cipher(), byte(), non_neg_integer()) :: byte()
  defp apply_operation(:reversebits, byte, _index), do: reversebits(byte)
  defp apply_operation({:xor, n}, byte, _index), do: xor_n(byte, n)
  defp apply_operation(:xorpos, byte, pos), do: xor_pos(byte, pos)
  defp apply_operation({:add, n}, byte, _index), do: add_n(byte, n)
  defp apply_operation(:addpos, byte, pos), do: add_pos(byte, pos)
  defp apply_operation({:sub, n}, byte, _index), do: sub(byte, n)
  defp apply_operation(:subpos, byte, pos), do: sub_pos(byte, pos)

  # Reverse the order of bits in the byte, so the least-significant bit becomes
  # the most-significant bit, the 2nd-least-significant becomes the 2nd-most-significant, and so on.
  @spec reversebits(byte()) :: byte()
  def reversebits(byte) do
    <<b7::1, b6::1, b5::1, b4::1, b3::1, b2::1, b1::1, b0::1>> = <<byte>>
    # notice <<reserved>> and reserved represent the same underlying byte, but not the same
    # elixir value
    <<reversed>> = <<b0::1, b1::1, b2::1, b3::1, b4::1, b5::1, b6::1, b7::1>>
    reversed
  end

  # XOR means "eXclusive OR".
  # A XOR B XOR B == A is why XOR is used in encryption, checksums, and data toggling.
  # XOR the byte by the value N. Note that 0 is a valid value for N.
  # 0 is a valid value for n.
  # For example, if n is 1, then input hex "68 65 6c 6c 6f"
  # becomes "69 64 6d 6d 6e"
  @spec xor_n(byte(), non_neg_integer()) :: byte()
  def xor_n(byte, n) do
    Bitwise.bxor(byte, n)
  end

  # XOR the byte by its position in the stream, starting from 0.
  @spec xor_pos(byte(), non_neg_integer()) :: byte()
  def xor_pos(byte, pos) do
    Bitwise.bxor(byte, pos)
  end

  @spec add_n(byte(), non_neg_integer()) :: byte()
  def add_n(byte, n) do
    rem(byte + n, 256)
  end

  # Add the position in the stream to the byte, modulo 256,
  # starting from 0. Addition wraps, so that 255+1=0, 255+2=1, and so on.

  @spec add_pos(byte(), non_neg_integer()) :: byte()
  def add_pos(byte, pos) do
    rem(byte + pos, 256)
  end

  @spec sub(byte(), non_neg_integer()) :: byte()
  def sub(byte, n) do
    rem(byte - n, 256)
  end

  @spec sub_pos(byte(), non_neg_integer()) :: byte()
  def sub_pos(byte, pos) do
    rem(byte - pos, 256)
  end

  # parse cipher specs
  @spec parse_cipher_spec(binary()) :: {:ok, ciphers(), binary()} | :error
  def parse_cipher_spec(binary) when is_binary(binary) do
    parse_cipher_spec(binary, _acc = [])
  end

  defp parse_cipher_spec(<<0x00, rest::binary>>, acc), do: {:ok, acc |> Enum.reverse(), rest}

  defp parse_cipher_spec(<<0x01, rest::binary>>, acc),
    do: parse_cipher_spec(rest, [:reversebits] ++ acc)

  defp parse_cipher_spec(<<0x02, n, rest::binary>>, acc),
    do: parse_cipher_spec(rest, [{:xor, n}] ++ acc)

  defp parse_cipher_spec(<<0x03, rest::binary>>, acc),
    do: parse_cipher_spec(rest, [:xorpos] ++ acc)

  defp parse_cipher_spec(<<0x04, n, rest::binary>>, acc),
    do: parse_cipher_spec(rest, [{:add, n}] ++ acc)

  defp parse_cipher_spec(<<0x05, rest::binary>>, acc),
    do: parse_cipher_spec(rest, [:addpos] ++ acc)

  defp parse_cipher_spec(_other, _accacc), do: :error

  @spec reverse_ciphers(ciphers()) :: ciphers()
  def reverse_ciphers(ciphers) do
    ciphers
    |> Enum.reverse()
    |> Enum.map(&apply_reversed_cipher(&1))
  end

  @spec apply_reversed_cipher(cipher()) :: cipher()
  defp apply_reversed_cipher(:addpos), do: :subpos
  defp apply_reversed_cipher({:add, n}), do: {:sub, n}
  defp apply_reversed_cipher(other), do: other

  @spec no_op_ciphers?(ciphers()) :: boolean()
  def no_op_ciphers?(ciphers) do
    # Process ciphers to determine if they result in no-op
    {net_xor, net_add, reverse_count} =
      Enum.reduce(ciphers, {0, 0, 0}, &reduce_cipher/2)

    # Normalize add to handle negative values properly
    normalized_add = rem(rem(net_add, 256) + 256, 256)

    # Check if all operations cancel out:
    # - XOR operations combine via XOR (xor with 0 = no change)
    # - ADD/SUB operations combine via addition (add 0 = no change)
    # - REVERSEBITS operations cancel in pairs
    net_xor == 0 and normalized_add == 0 and rem(reverse_count, 2) == 0
  end

  defp reduce_cipher(cipher, {xor_acc, add_acc, rev_count}) do
    case cipher do
      :reversebits ->
        {xor_acc, add_acc, rev_count + 1}

      {:xor, n} ->
        {Bitwise.bxor(xor_acc, n), add_acc, rev_count}

      :xorpos ->
        # Position-dependent operations can't be statically determined as no-op
        # So we mark it as having effect
        {1, add_acc, rev_count}

      {:add, n} ->
        {xor_acc, add_acc + n, rev_count}

      :addpos ->
        {xor_acc, 1, rev_count}

      {:sub, n} ->
        {xor_acc, add_acc - n, rev_count}

      :subpos ->
        {xor_acc, 1, rev_count}
    end
  end
end
