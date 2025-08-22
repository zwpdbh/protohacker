defmodule Protohacker.BudgetChat.Common do
  def ensure_newline(message) when is_binary(message) do
    if String.ends_with?(message, "\n") do
      message
    else
      message <> "\n"
    end
  end
end
