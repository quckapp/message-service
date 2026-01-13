import Config

if config_env() == :prod do
  config :message_service, MessageService.Endpoint,
    url: [host: System.get_env("PHX_HOST") || "localhost", port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT") || "4003")],
    secret_key_base: System.get_env("SECRET_KEY_BASE") || raise("SECRET_KEY_BASE missing")

  config :message_service, :mongodb,
    url: System.get_env("MONGODB_URI") || raise("MONGODB_URI missing"),
    pool_size: String.to_integer(System.get_env("MONGODB_POOL_SIZE") || "20")

  config :message_service, :redis,
    host: System.get_env("REDIS_HOST"),
    port: String.to_integer(System.get_env("REDIS_PORT") || "6379"),
    password: System.get_env("REDIS_PASSWORD")

  config :message_service, MessageService.Guardian, secret_key: System.get_env("JWT_SECRET")
end
