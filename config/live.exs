# =============================================================================
# LIVE Environment Configuration
# =============================================================================
# Use this profile for live environment (same as production with stricter settings)
# Run with: MIX_ENV=live mix phx.server
# =============================================================================

import Config

config :message_service, MessageService.Endpoint,
  http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT") || "4004")],
  url: [host: System.get_env("PHX_HOST") || "localhost", port: 443, scheme: "https"],
  secret_key_base: System.get_env("SECRET_KEY_BASE") || raise("SECRET_KEY_BASE missing"),
  server: true,
  cache_static_manifest: "priv/static/cache_manifest.json"

# MongoDB - Live (highest pool size)
config :message_service, :mongodb,
  url: System.get_env("MONGODB_URI") || raise("MONGODB_URI missing"),
  pool_size: String.to_integer(System.get_env("MONGODB_POOL_SIZE") || "100"),
  timeout: 15_000,
  connect_timeout: 10_000

# Redis - Live
config :message_service, :redis,
  host: System.get_env("REDIS_HOST") || raise("REDIS_HOST missing"),
  port: String.to_integer(System.get_env("REDIS_PORT") || "6379"),
  password: System.get_env("REDIS_PASSWORD"),
  database: String.to_integer(System.get_env("REDIS_DATABASE") || "5"),
  pool_size: 64,
  ssl: System.get_env("REDIS_SSL") == "true"

# Kafka - Live
config :message_service, :kafka,
  brokers: String.split(System.get_env("KAFKA_BROKERS") || "localhost:9092", ","),
  consumer_group: "message-service-live",
  ssl: System.get_env("KAFKA_SSL") == "true"

# JWT
config :message_service, MessageService.Guardian,
  issuer: "quckapp-auth",
  secret_key: System.get_env("JWT_SECRET") || raise("JWT_SECRET missing")

# libcluster - Kubernetes DNS strategy for Live
config :libcluster,
  topologies: [
    message_cluster: [
      strategy: Cluster.Strategy.Kubernetes.DNS,
      config: [
        service: System.get_env("CLUSTER_SERVICE_NAME") || "message-service-headless",
        application_name: "message_service",
        polling_interval: 5_000
      ]
    ]
  ]

# Services
config :message_service, :services,
  auth_service_url: System.get_env("AUTH_SERVICE_URL") || raise("AUTH_SERVICE_URL missing"),
  user_service_url: System.get_env("USER_SERVICE_URL") || raise("USER_SERVICE_URL missing")

# Logging - Error level only for live
config :logger, level: :error
