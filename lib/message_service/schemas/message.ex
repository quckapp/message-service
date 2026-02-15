defmodule MessageService.Schemas.Message do
  @moduledoc """
  Message-related schemas for the Message Service API.
  """
  alias OpenApiSpex.Schema
  require OpenApiSpex

  defmodule Reaction do
    @moduledoc "Message reaction schema"
    OpenApiSpex.schema(%{
      title: "Reaction",
      description: "A reaction on a message",
      type: :object,
      properties: %{
        emoji: %Schema{type: :string, description: "The emoji used for the reaction", example: "thumbs_up"},
        user_ids: %Schema{type: :array, items: %Schema{type: :string}, description: "List of user IDs who added this reaction"}
      },
      required: [:emoji, :user_ids]
    })
  end

  defmodule MessageType do
    @moduledoc "Message type enumeration"
    OpenApiSpex.schema(%{
      title: "MessageType",
      description: "Type of message content",
      type: :string,
      enum: ["text", "image", "file", "audio", "video", "system", "sticker", "gif"]
    })
  end

  defmodule Message do
    @moduledoc "Complete message object"
    OpenApiSpex.schema(%{
      title: "Message",
      description: "A message in a conversation",
      type: :object,
      properties: %{
        id: %Schema{type: :string, description: "Unique message identifier", example: "msg_abc123def456"},
        conversation_id: %Schema{type: :string, description: "ID of the conversation this message belongs to", example: "conv_xyz789"},
        sender_id: %Schema{type: :string, description: "ID of the user who sent the message", example: "user_123"},
        content: %Schema{type: :string, description: "Message content", example: "Hello, how are you?"},
        type: MessageType,
        attachments: %Schema{
          type: :array,
          description: "List of attachments",
          items: %Schema{
            type: :object,
            properties: %{
              id: %Schema{type: :string, description: "Attachment ID"},
              url: %Schema{type: :string, description: "Attachment URL"},
              type: %Schema{type: :string, description: "Attachment type"},
              name: %Schema{type: :string, description: "Attachment filename"},
              size: %Schema{type: :integer, description: "File size in bytes"}
            }
          }
        },
        reactions: %Schema{
          type: :array,
          description: "List of reactions on this message",
          items: Reaction
        },
        reply_to: %Schema{type: :string, nullable: true, description: "ID of the message this is replying to"},
        mentions: %Schema{type: :array, items: %Schema{type: :string}, description: "List of mentioned user IDs"},
        edited: %Schema{type: :boolean, description: "Whether the message has been edited"},
        edited_at: %Schema{type: :string, format: "date-time", nullable: true, description: "When the message was last edited"},
        deleted: %Schema{type: :boolean, description: "Whether the message has been deleted"},
        created_at: %Schema{type: :string, format: "date-time", description: "When the message was created"},
        updated_at: %Schema{type: :string, format: "date-time", description: "When the message was last updated"}
      },
      required: [:id, :conversation_id, :sender_id, :content, :type, :created_at]
    })
  end

  defmodule SendMessageRequest do
    @moduledoc "Request to send a new message"
    OpenApiSpex.schema(%{
      title: "SendMessageRequest",
      description: "Request body for sending a new message",
      type: :object,
      properties: %{
        conversation_id: %Schema{type: :string, description: "ID of the conversation to send the message to", example: "conv_xyz789"},
        content: %Schema{type: :string, description: "Message content", example: "Hello, world!"},
        type: %Schema{type: :string, enum: ["text", "image", "file", "audio", "video", "sticker", "gif"], description: "Type of message", default: "text"},
        metadata: %Schema{type: :object, description: "Additional metadata for the message", additionalProperties: true},
        reply_to: %Schema{type: :string, nullable: true, description: "ID of the message being replied to"},
        attachments: %Schema{
          type: :array,
          description: "List of attachment IDs to include",
          items: %Schema{type: :string}
        },
        mentions: %Schema{
          type: :array,
          description: "List of user IDs mentioned in the message",
          items: %Schema{type: :string}
        }
      },
      required: [:conversation_id, :content, :type],
      example: %{
        conversation_id: "conv_xyz789",
        content: "Hello, world!",
        type: "text",
        mentions: ["user_456", "user_789"],
        reply_to: nil
      }
    })
  end

  defmodule MessageResponse do
    @moduledoc "Response containing a single message"
    OpenApiSpex.schema(%{
      title: "MessageResponse",
      description: "Response containing a single message",
      type: :object,
      properties: %{
        success: %Schema{type: :boolean, description: "Operation success status"},
        data: Message
      },
      required: [:success, :data]
    })
  end

  defmodule MessageListResponse do
    @moduledoc "Response containing a list of messages"
    OpenApiSpex.schema(%{
      title: "MessageListResponse",
      description: "Response containing a list of messages",
      type: :object,
      properties: %{
        success: %Schema{type: :boolean, description: "Operation success status"},
        data: %Schema{type: :array, items: Message, description: "List of messages"}
      },
      required: [:success, :data]
    })
  end

  defmodule EditMessageRequest do
    @moduledoc "Request to edit a message"
    OpenApiSpex.schema(%{
      title: "EditMessageRequest",
      description: "Request body for editing an existing message",
      type: :object,
      properties: %{
        content: %Schema{type: :string, description: "New message content", example: "Updated message content"}
      },
      required: [:content],
      example: %{
        content: "Updated message content"
      }
    })
  end

  defmodule DeleteMessageRequest do
    @moduledoc "Request to delete a message"
    OpenApiSpex.schema(%{
      title: "DeleteMessageRequest",
      description: "Request body for deleting a message",
      type: :object,
      properties: %{
        for_everyone: %Schema{type: :boolean, description: "Delete for all users in the conversation", default: false}
      },
      example: %{
        for_everyone: false
      }
    })
  end

  defmodule AddReactionRequest do
    @moduledoc "Request to add a reaction"
    OpenApiSpex.schema(%{
      title: "AddReactionRequest",
      description: "Request body for adding a reaction to a message",
      type: :object,
      properties: %{
        emoji: %Schema{type: :string, description: "Emoji identifier for the reaction", example: "thumbs_up"}
      },
      required: [:emoji],
      example: %{
        emoji: "thumbs_up"
      }
    })
  end

  defmodule MarkReadRequest do
    @moduledoc "Request to mark messages as read"
    OpenApiSpex.schema(%{
      title: "MarkReadRequest",
      description: "Request body for marking messages as read",
      type: :object,
      properties: %{
        message_ids: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: "List of message IDs to mark as read"
        }
      },
      required: [:message_ids],
      example: %{
        message_ids: ["msg_abc123", "msg_def456", "msg_ghi789"]
      }
    })
  end

  defmodule MarkDeliveredRequest do
    @moduledoc "Request to mark messages as delivered"
    OpenApiSpex.schema(%{
      title: "MarkDeliveredRequest",
      description: "Request body for marking messages as delivered",
      type: :object,
      properties: %{
        message_ids: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: "List of message IDs to mark as delivered"
        }
      },
      required: [:message_ids],
      example: %{
        message_ids: ["msg_abc123", "msg_def456"]
      }
    })
  end

  defmodule SearchRequest do
    @moduledoc "Search messages request parameters"
    OpenApiSpex.schema(%{
      title: "SearchRequest",
      description: "Parameters for searching messages in a conversation",
      type: :object,
      properties: %{
        q: %Schema{type: :string, description: "Search query string", example: "meeting tomorrow"},
        limit: %Schema{type: :integer, description: "Maximum number of results to return", default: 20, minimum: 1, maximum: 100},
        before: %Schema{type: :string, format: "date-time", description: "Search for messages before this timestamp"},
        after: %Schema{type: :string, format: "date-time", description: "Search for messages after this timestamp"}
      },
      required: [:q],
      example: %{
        q: "meeting tomorrow",
        limit: 20
      }
    })
  end

  defmodule DeleteMessageResponse do
    @moduledoc "Response for message deletion"
    OpenApiSpex.schema(%{
      title: "DeleteMessageResponse",
      description: "Response for message deletion operation",
      type: :object,
      properties: %{
        success: %Schema{type: :boolean, description: "Operation success status"},
        data: %Schema{
          type: :object,
          properties: %{
            deleted: %Schema{type: :boolean, description: "Whether the message was deleted"},
            message_id: %Schema{type: :string, description: "ID of the deleted message"}
          }
        }
      },
      required: [:success]
    })
  end
end
