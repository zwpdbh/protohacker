defmodule Protohacker.InsecureSocketLayer.MessageParser do
  import NimbleParsec

  toy_number =
    ignore(ascii_string([?\s], min: 0))
    |> integer(min: 1)
    |> ignore(string("x"))

  word = ascii_string([?a..?z, ?A..?Z], min: 1)

  toy_item =
    word
    |> repeat(
      ignore(ascii_string([?\s], min: 1))
      |> concat(word)
    )
    |> reduce({:join_words, []})

  toy_order =
    toy_number
    # space after "x"
    |> ignore(string(" "))
    |> concat(toy_item)
    |> reduce({:make_toy_entry, []})

  # optional whitespace before
  comma_separator =
    ignore(ascii_string([?\s], min: 0))
    |> ignore(string(","))
    # optional whitespace after
    |> ignore(ascii_string([?\s], min: 0))

  toy_order_list =
    toy_order
    |> repeat(
      comma_separator
      |> concat(toy_order)
    )
    |> ignore(ascii_string([?\s], min: 0))

  defparsec(:parse_toy_order_list, toy_order_list)

  defp join_words([first | rest]) do
    [first | rest]
    |> Enum.join(" ")
  end

  defp make_toy_entry([count, name]) do
    {count, name}
  end

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
    case line |> parse_toy_order_list do
      {:ok, entries, "" = _rest, %{}, _line, _column} ->
        entries
        |> Enum.max_by(fn {count, _name} -> count end)
        |> format_toy_entry()

      {:error, reason, rest, _context, line, column} ->
        reason |> dbg()

        raise "Parse error at #{inspect(line)}:#{column} - #{inspect(reason)}, remaining: #{inspect(rest)}"
    end
  end

  defp format_toy_entry({count, name}) do
    "#{count}x #{name}"
  end
end
