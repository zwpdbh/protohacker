# config/test.exs
import Config

config :protohacker,
  budget_chat_server: ~c"localhost",
  budget_chat_server_port: 3007

# Do not include metadata nor timestamps in development logs
config :logger, :default_formatter, format: "[$level] $message\n"
