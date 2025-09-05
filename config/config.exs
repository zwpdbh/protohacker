# config/config.exs
import Config

config :protohacker,
  budget_chat_server: ~c"chat.protohackers.com",
  budget_chat_server_port: 16963

# Define a reusable formatter config
config :logger, :default_formatter,
  format: "\n$time [$level] $metadata\n $message\n",
  metadata: [:file, :line]

# Tell the console backend to use it
config :logger,
       :console,
       format: :default_formatter

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config("#{config_env()}.exs")
