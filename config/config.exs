# config/config.exs
import Config

config :protohacker,
  budget_chat_server: ~c"chat.protohackers.com",
  budget_chat_server_port: 16963

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
