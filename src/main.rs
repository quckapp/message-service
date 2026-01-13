use actix_web::{web, App, HttpServer, HttpResponse, middleware};
use mongodb::{Client, options::ClientOptions, Database};
use std::env;
use tracing_subscriber;

mod api;
mod models;
mod services;
mod config;
mod db;

use api::routes;

pub struct AppState {
    pub db: Database,
    pub redis: Option<redis::Client>,
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    dotenv::dotenv().ok();
    tracing_subscriber::fmt::init();

    let mongo_uri = env::var("MONGODB_URI").unwrap_or_else(|_| "mongodb://localhost:27017".to_string());
    let db_name = env::var("DATABASE_NAME").unwrap_or_else(|_| "quckchat_messages".to_string());
    let port = env::var("PORT").unwrap_or_else(|_| "3004".to_string());

    let client_options = ClientOptions::parse(&mongo_uri).await.expect("Failed to parse MongoDB URI");
    let client = Client::with_options(client_options).expect("Failed to create MongoDB client");
    let db = client.database(&db_name);

    let redis_client = env::var("REDIS_URL").ok().and_then(|url| redis::Client::open(url).ok());

    let state = web::Data::new(AppState { db, redis: redis_client });

    tracing::info!("Message service starting on port {}", port);

    HttpServer::new(move || {
        App::new()
            .app_data(state.clone())
            .wrap(middleware::Logger::default())
            .wrap(middleware::Compress::default())
            .route("/health", web::get().to(health_check))
            .service(
                web::scope("/api/v1")
                    .configure(routes::configure)
            )
    })
    .bind(format!("0.0.0.0:{}", port))?
    .run()
    .await
}

async fn health_check() -> HttpResponse {
    HttpResponse::Ok().json(serde_json::json!({
        "status": "healthy",
        "service": "message-service"
    }))
}
