import Config

config :message_service, MessageService.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4006],
  check_origin: false, debug_errors: true,
  secret_key_base: "dev_secret_key_base_message_service",
  watchers: []

# MongoDB configuration for development
config :message_service, :mongodb,
  url: "mongodb://localhost:27017/quckapp_messages_dev",
  pool_size: 5

# Redis configuration for development
config :message_service, :redis,
  host: "localhost",
  port: 6379,
  database: 5

# Kafka configuration for development (disabled by default)
config :message_service, :kafka,
  enabled: false,
  brokers: [{~c"localhost", 9092}],
  consumer_group: "message-service-group-dev"

# Guardian JWT configuration for development
config :message_service, MessageService.Guardian,
  issuer: "message_service",
  secret_key: "dev_jwt_secret_for_message_service"

# libcluster topology for development (no clustering)
config :libcluster, topologies: []

config :logger, :console, format: "[$level] $message\n"
config :phoenix, :plug_init_mode, :runtime
