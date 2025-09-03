# config/test.exs
import Config

config :protohacker,
  budget_chat_server: ~c"localhost",
  budget_chat_server_port: 3007

config :logger,
  format: "$time $metadata[$level] $message\n",
  metadata: :role
