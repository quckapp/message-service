use actix_web::{web, HttpResponse};
use bson::{doc, oid::ObjectId};
use chrono::Utc;
use futures::stream::TryStreamExt;
use mongodb::options::FindOptions;

use crate::models::*;
use crate::AppState;

pub async fn create_message(
    state: web::Data<AppState>,
    body: web::Json<CreateMessageRequest>,
) -> HttpResponse {
    let collection = state.db.collection::<Message>("messages");

    let message = Message {
        id: None,
        channel_id: body.channel_id.clone(),
        user_id: body.user_id.clone(),
        content: body.content.clone(),
        thread_id: body.thread_id.clone(),
        parent_message_id: body.parent_message_id.clone(),
        message_type: MessageType::Text,
        attachments: body.attachments.clone(),
        mentions: body.mentions.clone(),
        reactions: vec![],
        edited_at: None,
        deleted_at: None,
        is_pinned: false,
        created_at: Utc::now(),
        updated_at: Utc::now(),
    };

    match collection.insert_one(message.clone(), None).await {
        Ok(result) => {
            let mut msg = message;
            msg.id = result.inserted_id.as_object_id();
            HttpResponse::Created().json(msg)
        }
        Err(e) => HttpResponse::InternalServerError().json(serde_json::json!({
            "error": format!("Failed to create message: {}", e)
        })),
    }
}

pub async fn get_message(
    state: web::Data<AppState>,
    path: web::Path<String>,
) -> HttpResponse {
    let collection = state.db.collection::<Message>("messages");
    let id = path.into_inner();

    let object_id = match ObjectId::parse_str(&id) {
        Ok(oid) => oid,
        Err(_) => return HttpResponse::BadRequest().json(serde_json::json!({"error": "Invalid ID"})),
    };

    match collection.find_one(doc! { "_id": object_id, "deleted_at": null }, None).await {
        Ok(Some(message)) => HttpResponse::Ok().json(message),
        Ok(None) => HttpResponse::NotFound().json(serde_json::json!({"error": "Message not found"})),
        Err(e) => HttpResponse::InternalServerError().json(serde_json::json!({"error": e.to_string()})),
    }
}

pub async fn list_messages(
    state: web::Data<AppState>,
    query: web::Query<MessageQueryParams>,
) -> HttpResponse {
    let collection = state.db.collection::<Message>("messages");
    let limit = query.limit.unwrap_or(50).min(100);

    let mut filter = doc! { "deleted_at": null };

    if let Some(channel_id) = &query.channel_id {
        filter.insert("channel_id", channel_id);
    }
    if let Some(user_id) = &query.user_id {
        filter.insert("user_id", user_id);
    }

    let options = FindOptions::builder()
        .sort(doc! { "created_at": -1 })
        .limit(limit)
        .build();

    match collection.find(filter, options).await {
        Ok(cursor) => {
            let messages: Vec<Message> = cursor.try_collect().await.unwrap_or_default();
            HttpResponse::Ok().json(MessagesResponse {
                has_more: messages.len() as i64 == limit,
                cursor: messages.last().and_then(|m| m.id.map(|id| id.to_hex())),
                messages,
            })
        }
        Err(e) => HttpResponse::InternalServerError().json(serde_json::json!({"error": e.to_string()})),
    }
}

pub async fn update_message(
    state: web::Data<AppState>,
    path: web::Path<String>,
    body: web::Json<UpdateMessageRequest>,
) -> HttpResponse {
    let collection = state.db.collection::<Message>("messages");
    let id = path.into_inner();

    let object_id = match ObjectId::parse_str(&id) {
        Ok(oid) => oid,
        Err(_) => return HttpResponse::BadRequest().json(serde_json::json!({"error": "Invalid ID"})),
    };

    let mut update = doc! { "$set": { "updated_at": Utc::now(), "edited_at": Utc::now() } };
    if let Some(content) = &body.content {
        update.get_document_mut("$set").unwrap().insert("content", content);
    }

    match collection.update_one(doc! { "_id": object_id }, update, None).await {
        Ok(_) => HttpResponse::Ok().json(serde_json::json!({"message": "Updated"})),
        Err(e) => HttpResponse::InternalServerError().json(serde_json::json!({"error": e.to_string()})),
    }
}

pub async fn delete_message(
    state: web::Data<AppState>,
    path: web::Path<String>,
) -> HttpResponse {
    let collection = state.db.collection::<Message>("messages");
    let id = path.into_inner();

    let object_id = match ObjectId::parse_str(&id) {
        Ok(oid) => oid,
        Err(_) => return HttpResponse::BadRequest().json(serde_json::json!({"error": "Invalid ID"})),
    };

    let update = doc! { "$set": { "deleted_at": Utc::now() } };
    match collection.update_one(doc! { "_id": object_id }, update, None).await {
        Ok(_) => HttpResponse::NoContent().finish(),
        Err(e) => HttpResponse::InternalServerError().json(serde_json::json!({"error": e.to_string()})),
    }
}

pub async fn add_reaction(
    state: web::Data<AppState>,
    path: web::Path<String>,
    body: web::Json<AddReactionRequest>,
) -> HttpResponse {
    let collection = state.db.collection::<Message>("messages");
    let id = path.into_inner();

    let object_id = match ObjectId::parse_str(&id) {
        Ok(oid) => oid,
        Err(_) => return HttpResponse::BadRequest().json(serde_json::json!({"error": "Invalid ID"})),
    };

    let update = doc! {
        "$addToSet": {
            "reactions": {
                "emoji": &body.emoji,
                "user_ids": [&body.user_id],
                "count": 1
            }
        }
    };

    match collection.update_one(doc! { "_id": object_id }, update, None).await {
        Ok(_) => HttpResponse::Ok().json(serde_json::json!({"message": "Reaction added"})),
        Err(e) => HttpResponse::InternalServerError().json(serde_json::json!({"error": e.to_string()})),
    }
}

pub async fn remove_reaction(
    state: web::Data<AppState>,
    path: web::Path<(String, String)>,
) -> HttpResponse {
    let (id, emoji) = path.into_inner();
    let collection = state.db.collection::<Message>("messages");

    let object_id = match ObjectId::parse_str(&id) {
        Ok(oid) => oid,
        Err(_) => return HttpResponse::BadRequest().json(serde_json::json!({"error": "Invalid ID"})),
    };

    let update = doc! {
        "$pull": {
            "reactions": { "emoji": emoji }
        }
    };

    match collection.update_one(doc! { "_id": object_id }, update, None).await {
        Ok(_) => HttpResponse::NoContent().finish(),
        Err(e) => HttpResponse::InternalServerError().json(serde_json::json!({"error": e.to_string()})),
    }
}

pub async fn pin_message(
    state: web::Data<AppState>,
    path: web::Path<String>,
) -> HttpResponse {
    let collection = state.db.collection::<Message>("messages");
    let id = path.into_inner();

    let object_id = match ObjectId::parse_str(&id) {
        Ok(oid) => oid,
        Err(_) => return HttpResponse::BadRequest().json(serde_json::json!({"error": "Invalid ID"})),
    };

    match collection.update_one(doc! { "_id": object_id }, doc! { "$set": { "is_pinned": true } }, None).await {
        Ok(_) => HttpResponse::Ok().json(serde_json::json!({"message": "Pinned"})),
        Err(e) => HttpResponse::InternalServerError().json(serde_json::json!({"error": e.to_string()})),
    }
}

pub async fn unpin_message(
    state: web::Data<AppState>,
    path: web::Path<String>,
) -> HttpResponse {
    let collection = state.db.collection::<Message>("messages");
    let id = path.into_inner();

    let object_id = match ObjectId::parse_str(&id) {
        Ok(oid) => oid,
        Err(_) => return HttpResponse::BadRequest().json(serde_json::json!({"error": "Invalid ID"})),
    };

    match collection.update_one(doc! { "_id": object_id }, doc! { "$set": { "is_pinned": false } }, None).await {
        Ok(_) => HttpResponse::Ok().json(serde_json::json!({"message": "Unpinned"})),
        Err(e) => HttpResponse::InternalServerError().json(serde_json::json!({"error": e.to_string()})),
    }
}

pub async fn get_channel_messages(
    state: web::Data<AppState>,
    path: web::Path<String>,
    query: web::Query<MessageQueryParams>,
) -> HttpResponse {
    let collection = state.db.collection::<Message>("messages");
    let channel_id = path.into_inner();
    let limit = query.limit.unwrap_or(50).min(100);

    let filter = doc! { "channel_id": &channel_id, "deleted_at": null, "thread_id": null };
    let options = FindOptions::builder()
        .sort(doc! { "created_at": -1 })
        .limit(limit)
        .build();

    match collection.find(filter, options).await {
        Ok(cursor) => {
            let messages: Vec<Message> = cursor.try_collect().await.unwrap_or_default();
            HttpResponse::Ok().json(MessagesResponse {
                has_more: messages.len() as i64 == limit,
                cursor: messages.last().and_then(|m| m.id.map(|id| id.to_hex())),
                messages,
            })
        }
        Err(e) => HttpResponse::InternalServerError().json(serde_json::json!({"error": e.to_string()})),
    }
}

pub async fn get_thread_messages(
    state: web::Data<AppState>,
    path: web::Path<String>,
    query: web::Query<MessageQueryParams>,
) -> HttpResponse {
    let collection = state.db.collection::<Message>("messages");
    let thread_id = path.into_inner();
    let limit = query.limit.unwrap_or(50).min(100);

    let filter = doc! { "thread_id": &thread_id, "deleted_at": null };
    let options = FindOptions::builder()
        .sort(doc! { "created_at": 1 })
        .limit(limit)
        .build();

    match collection.find(filter, options).await {
        Ok(cursor) => {
            let messages: Vec<Message> = cursor.try_collect().await.unwrap_or_default();
            HttpResponse::Ok().json(MessagesResponse {
                has_more: messages.len() as i64 == limit,
                cursor: None,
                messages,
            })
        }
        Err(e) => HttpResponse::InternalServerError().json(serde_json::json!({"error": e.to_string()})),
    }
}
