use std::env;

pub struct Config {
    pub port: u16,
    pub mongodb_uri: String,
    pub database_name: String,
    pub redis_url: Option<String>,
    pub kafka_brokers: String,
}

impl Config {
    pub fn from_env() -> Self {
        Config {
            port: env::var("PORT").unwrap_or_else(|_| "3004".to_string()).parse().unwrap_or(3004),
            mongodb_uri: env::var("MONGODB_URI").unwrap_or_else(|_| "mongodb://localhost:27017".to_string()),
            database_name: env::var("DATABASE_NAME").unwrap_or_else(|_| "quckchat_messages".to_string()),
            redis_url: env::var("REDIS_URL").ok(),
            kafka_brokers: env::var("KAFKA_BROKERS").unwrap_or_else(|_| "localhost:9092".to_string()),
        }
    }
}
