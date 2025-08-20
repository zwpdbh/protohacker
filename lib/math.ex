defmodule Math do
  @doc """
  Checks if a number n is prime.

  Returns true if n is prime, false otherwise.

  ## Examples

      iex> Prime.prime?(2)
      true

      iex> Prime.prime?(3)
      true

      iex> Prime.prime?(4)
      false

      iex> Prime.prime?(17)
      true

      iex> Prime.prime?(1)
      false
  """
  def prime?(n) when n < 2, do: false
  def prime?(2), do: true
  def prime?(n) when n > 2 and rem(n, 2) == 0, do: false

  def prime?(n) when n > 2 do
    # Check odd divisors from 3 up to √n
    limit = :math.sqrt(n) |> floor
    not Enum.any?(3..limit//2, &(rem(n, &1) == 0))
  end
end
