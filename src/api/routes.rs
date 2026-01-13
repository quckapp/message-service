use actix_web::web;
use super::handlers;

pub fn configure(cfg: &mut web::ServiceConfig) {
    cfg.service(
        web::scope("/messages")
            .route("", web::post().to(handlers::create_message))
            .route("", web::get().to(handlers::list_messages))
            .route("/{id}", web::get().to(handlers::get_message))
            .route("/{id}", web::put().to(handlers::update_message))
            .route("/{id}", web::delete().to(handlers::delete_message))
            .route("/{id}/reactions", web::post().to(handlers::add_reaction))
            .route("/{id}/reactions/{emoji}", web::delete().to(handlers::remove_reaction))
            .route("/{id}/pin", web::post().to(handlers::pin_message))
            .route("/{id}/unpin", web::post().to(handlers::unpin_message))
    )
    .service(
        web::scope("/channels/{channel_id}/messages")
            .route("", web::get().to(handlers::get_channel_messages))
    )
    .service(
        web::scope("/threads/{thread_id}/messages")
            .route("", web::get().to(handlers::get_thread_messages))
    );
}
