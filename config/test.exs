import Config

config :message_service, MessageService.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4004],
  secret_key_base: "test_secret",
  server: false

config :logger, level: :warning
