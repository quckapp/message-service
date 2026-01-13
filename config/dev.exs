import Config

config :message_service, MessageService.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4003],
  check_origin: false, debug_errors: true,
  secret_key_base: "dev_secret_key_base_message_service",
  watchers: []

config :logger, :console, format: "[$level] $message\n"
config :phoenix, :plug_init_mode, :runtime
