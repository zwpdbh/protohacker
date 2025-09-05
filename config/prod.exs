# config/test.exs
import Config

config :protohacker,
  budget_chat_server: ~c"chat.protohackers.com",
  budget_chat_server_port: 16963

# Do not print debug messages in production
config :logger, level: :info
