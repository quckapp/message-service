# =============================================================================
# LOCAL (Mock) Environment Configuration
# =============================================================================
# Use this profile for local development with Docker containers
# Run with: MIX_ENV=local mix phx.server
# =============================================================================

import Config

config :message_service, MessageService.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4004],
  check_origin: false,
  debug_errors: true,
  code_reloader: false,
  secret_key_base: "local_dev_secret_key_base_message_service_quckapp_32_chars"

# MongoDB - Local Docker
config :message_service, :mongodb,
  url: "mongodb://localhost:27017/quckapp_messages",
  pool_size: 5

# Redis - Local Docker
config :message_service, :redis,
  host: "localhost",
  port: 6379,
  password: nil,
  database: 5

# Kafka - Local Docker
config :message_service, :kafka,
  brokers: [{"localhost", 9092}],
  consumer_group: "message-service-local"

# JWT - Same secret as auth-service local
config :message_service, MessageService.Guardian,
  issuer: "quckapp-auth-local",
  secret_key: "bG9jYWwtZGV2LXNlY3JldC1rZXktZm9yLXRlc3Rpbmctb25seS0zMi1jaGFycw=="

# libcluster - Local gossip strategy
config :libcluster,
  topologies: [
    message_cluster: [
      strategy: Cluster.Strategy.Gossip
    ]
  ]

# Services
config :message_service, :services,
  auth_service_url: "http://localhost:8081",
  user_service_url: "http://localhost:8082"

# Logging - Verbose for local
config :logger, :console,
  format: "[$level] $message\n",
  level: :debug
