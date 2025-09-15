defmodule Protohacker.InsecureSocketLayer.MessageParser do
  @doc """
  Parses a toy request line and returns the toy with the highest copy count.

  ## Examples

      iex> Parser.find_max_toy("10x toy car,15x dog on a string,4x inflatable motorcycle")
      "15x dog on a string"

      iex> Parser.find_max_toy("1x a,2x b,3x c")
      "3x c"

      iex> Parser.find_max_toy("999x rare item")
      "999x rare item"
  """
  def find_max_toy(line) do
    line
    |> String.split(",", trim: true)
    |> Enum.map(&parse_toy_entry/1)
    |> Enum.max_by(fn {count, _name} -> count end)
    |> format_toy_entry()
  end

  # Parse a single entry like "10x toy car" → {10, "toy car"}
  defp parse_toy_entry(entry) do
    case Regex.run(~r/^(\d+)x\s+(.+)$/, entry, capture: :all_but_first) do
      [count_str, name] ->
        {String.to_integer(count_str), name}

      nil ->
        raise "Invalid toy entry: #{entry}"
    end
  end

  # Format back to "Nx name"
  defp format_toy_entry({count, name}) do
    "#{count}x #{name}"
  end
end
