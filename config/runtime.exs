import Config

# ==============================================================================
# Runtime Configuration
# This file is executed at runtime, after compilation
# ==============================================================================

if config_env() == :prod do
  # --------------------------------------------------------------------------
  # Endpoint Configuration
  # --------------------------------------------------------------------------
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "localhost"
  port = String.to_integer(System.get_env("PORT") || "4006")

  config :message_service, MessageService.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port,
      transport_options: [socket_opts: [:inet6]]
    ],
    secret_key_base: secret_key_base,
    server: true

  # --------------------------------------------------------------------------
  # MongoDB Configuration
  # --------------------------------------------------------------------------
  mongodb_url =
    System.get_env("MONGODB_URL") ||
      System.get_env("MONGODB_URI") ||
      raise """
      environment variable MONGODB_URL is missing.
      For example: mongodb://localhost:27017/message_service
      """

  mongodb_pool_size = String.to_integer(System.get_env("MONGODB_POOL_SIZE") || "20")

  config :message_service, :mongodb,
    url: mongodb_url,
    pool_size: mongodb_pool_size

  # --------------------------------------------------------------------------
  # Redis Configuration
  # --------------------------------------------------------------------------
  redis_url = System.get_env("REDIS_URL")
  redis_host = System.get_env("REDIS_HOST") || "localhost"
  redis_port = String.to_integer(System.get_env("REDIS_PORT") || "6379")
  redis_password = System.get_env("REDIS_PASSWORD")
  redis_database = String.to_integer(System.get_env("REDIS_DATABASE") || "5")

  redis_config =
    if redis_url do
      [url: redis_url]
    else
      config = [
        host: redis_host,
        port: redis_port,
        database: redis_database
      ]

      if redis_password && redis_password != "" do
        Keyword.put(config, :password, redis_password)
      else
        config
      end
    end

  config :message_service, :redis, redis_config

  # Phoenix PubSub Redis adapter
  config :message_service, MessageService.PubSub,
    adapter: Phoenix.PubSub.Redis,
    host: redis_host,
    port: redis_port,
    node_name: System.get_env("RELEASE_NODE") || "message_service"

  # --------------------------------------------------------------------------
  # Kafka Configuration
  # --------------------------------------------------------------------------
  kafka_enabled = System.get_env("KAFKA_ENABLED", "false") == "true"
  kafka_brokers_string = System.get_env("KAFKA_BROKERS") || "localhost:9092"

  kafka_brokers =
    kafka_brokers_string
    |> String.split(",")
    |> Enum.map(fn broker ->
      case String.split(String.trim(broker), ":") do
        [host, port] -> {String.to_charlist(host), String.to_integer(port)}
        [host] -> {String.to_charlist(host), 9092}
      end
    end)

  kafka_consumer_group = System.get_env("KAFKA_CONSUMER_GROUP") || "message-service-group"

  config :message_service, :kafka,
    enabled: kafka_enabled,
    brokers: kafka_brokers,
    consumer_group: kafka_consumer_group

  config :brod,
    clients: [
      message_service_kafka: [
        endpoints: kafka_brokers,
        auto_start_producers: true,
        default_producer_config: [
          required_acks: :all,
          ack_timeout: 10_000,
          max_retries: 3
        ]
      ]
    ]

  # --------------------------------------------------------------------------
  # Auth Service Configuration
  # --------------------------------------------------------------------------
  auth_service_url = System.get_env("AUTH_SERVICE_URL") || "http://localhost:4001"

  config :message_service, :auth_service,
    url: auth_service_url

  # --------------------------------------------------------------------------
  # Guardian JWT Configuration
  # --------------------------------------------------------------------------
  jwt_secret =
    System.get_env("JWT_SECRET") ||
      raise """
      environment variable JWT_SECRET is missing.
      """

  config :message_service, MessageService.Guardian,
    issuer: "message_service",
    secret_key: jwt_secret,
    ttl: {1, :day}

  # --------------------------------------------------------------------------
  # Clustering Configuration (libcluster)
  # --------------------------------------------------------------------------
  cluster_strategy = System.get_env("CLUSTER_STRATEGY") || "gossip"

  topologies =
    case cluster_strategy do
      "kubernetes" ->
        kubernetes_namespace = System.get_env("KUBERNETES_NAMESPACE") || "default"
        kubernetes_selector = System.get_env("KUBERNETES_SELECTOR") || "app=message-service"

        [
          k8s: [
            strategy: Cluster.Strategy.Kubernetes,
            config: [
              mode: :dns,
              kubernetes_node_basename: "message_service",
              kubernetes_selector: kubernetes_selector,
              kubernetes_namespace: kubernetes_namespace
            ]
          ]
        ]

      "dns" ->
        dns_query = System.get_env("DNS_CLUSTER_QUERY") || "message-service.local"

        [
          dns: [
            strategy: Cluster.Strategy.DNSPoll,
            config: [
              polling_interval: 5_000,
              query: dns_query,
              node_basename: "message_service"
            ]
          ]
        ]

      _ ->
        # Default gossip strategy for local development
        [
          gossip: [
            strategy: Cluster.Strategy.Gossip,
            config: [
              port: 45892,
              if_addr: {0, 0, 0, 0},
              multicast_if: {0, 0, 0, 0},
              multicast_addr: {230, 1, 1, 251},
              multicast_ttl: 1
            ]
          ]
        ]
    end

  config :libcluster, topologies: topologies

  # --------------------------------------------------------------------------
  # Logger Configuration
  # --------------------------------------------------------------------------
  log_level =
    case System.get_env("LOG_LEVEL", "info") do
      "debug" -> :debug
      "info" -> :info
      "warn" -> :warning
      "warning" -> :warning
      "error" -> :error
      _ -> :info
    end

  config :logger, level: log_level

  config :logger, :console,
    format: "$time $metadata[$level] $message\n",
    metadata: [:request_id, :user_id, :conversation_id]

  # --------------------------------------------------------------------------
  # Finch HTTP Client Configuration
  # --------------------------------------------------------------------------
  config :message_service, MessageService.Finch,
    pools: %{
      :default => [size: 10, count: 1],
      auth_service_url => [size: 25, count: 2]
    }
end
