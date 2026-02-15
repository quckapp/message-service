import Config

config :message_service, namespace: MessageService

config :message_service, MessageService.Endpoint,
  url: [host: "localhost"],
  render_errors: [formats: [json: MessageService.ErrorJSON], layout: false],
  pubsub_server: MessageService.PubSub

config :message_service, :mongodb,
  url: System.get_env("MONGODB_URI") || "mongodb://localhost:27017/quckapp_messages",
  pool_size: 10

config :message_service, :redis,
  host: System.get_env("REDIS_HOST") || "localhost",
  port: String.to_integer(System.get_env("REDIS_PORT") || "6379"),
  database: 5

config :message_service, :kafka,
  enabled: false,
  brokers: [{~c"localhost", 9092}],
  consumer_group: "message-service-group"

config :message_service, MessageService.Guardian,
  issuer: "quckapp",
  secret_key: System.get_env("JWT_SECRET") || "your-secret-key"

config :libcluster, topologies: [message_cluster: [strategy: Cluster.Strategy.Gossip]]
config :logger, :console, format: "$time $metadata[$level] $message\n", metadata: [:request_id, :conversation_id]
config :phoenix, :json_library, Jason

# Import environment-specific config
# Environments: dev, test, local, qa, uat1, uat2, uat3, staging, production, live, prod
if File.exists?("config/#{config_env()}.exs") do
  import_config "#{config_env()}.exs"
end
