# config/test.exs
import Config

# During test, set the budget_chat_server to be the service running locally
config :protohacker,
  budget_chat_server: ~c"localhost",
  budget_chat_server_port: 3007

config :logger,
  level: :warning
