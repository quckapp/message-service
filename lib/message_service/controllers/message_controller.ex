defmodule MessageService.MessageController do
  use Phoenix.Controller, formats: [:json]
  use OpenApiSpex.ControllerSpecs

  alias MessageService.Schemas.Message
  alias MessageService.Schemas.Common

  tags ["Messages"]
  security [%{"bearer_auth" => []}, %{"api_key" => []}]

  operation :send,
    summary: "Send a message",
    description: "Send a new message to a conversation",
    request_body: {"Message data", "application/json", Message.SendMessageRequest},
    responses: [
      ok: {"Message sent successfully", "application/json", Message.MessageResponse},
      bad_request: {"Invalid request", "application/json", Common.ErrorResponse},
      unauthorized: {"Unauthorized", "application/json", Common.ErrorResponse}
    ]

  def send(conn, %{"conversation_id" => conv_id, "type" => type, "content" => content} = params) do
    user_id = conn.assigns[:current_user_id]
    type_atom = String.to_existing_atom(type)
    opts = [
      attachments: Map.get(params, "attachments", []),
      reply_to: Map.get(params, "reply_to"),
      mentions: Map.get(params, "mentions", [])
    ]
    
    case MessageService.MessageManager.send_message(conv_id, user_id, type_atom, content, opts) do
      {:ok, message} -> json(conn, %{success: true, data: message})
      {:error, reason} -> conn |> put_status(400) |> json(%{success: false, error: reason})
    end
  rescue
    ArgumentError -> conn |> put_status(400) |> json(%{success: false, error: "Invalid message type"})
  end

  operation :index,
    summary: "List messages in a conversation",
    description: "Retrieve a paginated list of messages from a specific conversation",
    parameters: [
      conversation_id: [
        in: :path,
        type: :string,
        required: true,
        description: "The conversation ID",
        example: "conv_xyz789"
      ],
      limit: [
        in: :query,
        type: :integer,
        required: false,
        description: "Maximum number of messages to return",
        example: 50
      ],
      before: [
        in: :query,
        type: :string,
        required: false,
        description: "Cursor for messages before this ID"
      ],
      after: [
        in: :query,
        type: :string,
        required: false,
        description: "Cursor for messages after this ID"
      ]
    ],
    responses: [
      ok: {"Messages retrieved successfully", "application/json", Message.MessageListResponse},
      unauthorized: {"Unauthorized", "application/json", Common.ErrorResponse}
    ]

  def index(conn, %{"conversation_id" => conv_id} = params) do
    opts = [
      limit: String.to_integer(Map.get(params, "limit", "50")),
      before: Map.get(params, "before"),
      after: Map.get(params, "after")
    ]
    {:ok, messages} = MessageService.MessageManager.get_messages(conv_id, opts)
    json(conn, %{success: true, data: messages})
  end

  operation :show,
    summary: "Get a message",
    description: "Retrieve a specific message by its ID",
    parameters: [
      message_id: [
        in: :path,
        type: :string,
        required: true,
        description: "The message ID",
        example: "msg_abc123def456"
      ]
    ],
    responses: [
      ok: {"Message retrieved successfully", "application/json", Message.MessageResponse},
      not_found: {"Message not found", "application/json", Common.ErrorResponse},
      unauthorized: {"Unauthorized", "application/json", Common.ErrorResponse}
    ]

  def show(conn, %{"message_id" => message_id}) do
    case MessageService.MessageManager.get_message(message_id) do
      {:ok, nil} -> conn |> put_status(404) |> json(%{success: false, error: "Message not found"})
      {:ok, message} -> json(conn, %{success: true, data: message})
    end
  end

  operation :edit,
    summary: "Edit a message",
    description: "Edit the content of an existing message. Only the message sender can edit their messages.",
    parameters: [
      message_id: [
        in: :path,
        type: :string,
        required: true,
        description: "The message ID",
        example: "msg_abc123def456"
      ]
    ],
    request_body: {"Updated message content", "application/json", Message.EditMessageRequest},
    responses: [
      ok: {"Message updated successfully", "application/json", Message.MessageResponse},
      bad_request: {"Invalid request or not authorized", "application/json", Common.ErrorResponse},
      unauthorized: {"Unauthorized", "application/json", Common.ErrorResponse}
    ]

  def edit(conn, %{"message_id" => message_id, "content" => content}) do
    user_id = conn.assigns[:current_user_id]
    case MessageService.MessageManager.edit_message(message_id, user_id, content) do
      {:ok, message} -> json(conn, %{success: true, data: message})
      {:error, reason} -> conn |> put_status(400) |> json(%{success: false, error: reason})
    end
  end

  operation :delete,
    summary: "Delete a message",
    description: "Delete a message. Can delete for self only or for everyone in the conversation.",
    parameters: [
      message_id: [
        in: :path,
        type: :string,
        required: true,
        description: "The message ID",
        example: "msg_abc123def456"
      ],
      for_everyone: [
        in: :query,
        type: :boolean,
        required: false,
        description: "Delete for all users in the conversation",
        example: false
      ]
    ],
    responses: [
      ok: {"Message deleted successfully", "application/json", Message.DeleteMessageResponse},
      bad_request: {"Invalid request or not authorized", "application/json", Common.ErrorResponse},
      unauthorized: {"Unauthorized", "application/json", Common.ErrorResponse}
    ]

  def delete(conn, %{"message_id" => message_id} = params) do
    user_id = conn.assigns[:current_user_id]
    for_everyone = Map.get(params, "for_everyone", false)
    case MessageService.MessageManager.delete_message(message_id, user_id, for_everyone) do
      {:ok, result} -> json(conn, %{success: true, data: result})
      {:error, reason} -> conn |> put_status(400) |> json(%{success: false, error: reason})
    end
  end

  operation :add_reaction,
    summary: "Add a reaction to a message",
    description: "Add an emoji reaction to a message",
    parameters: [
      message_id: [
        in: :path,
        type: :string,
        required: true,
        description: "The message ID",
        example: "msg_abc123def456"
      ]
    ],
    request_body: {"Reaction data", "application/json", Message.AddReactionRequest},
    responses: [
      ok: {"Reaction added successfully", "application/json", Message.MessageResponse},
      bad_request: {"Invalid request", "application/json", Common.ErrorResponse},
      unauthorized: {"Unauthorized", "application/json", Common.ErrorResponse}
    ]

  def add_reaction(conn, %{"message_id" => message_id, "emoji" => emoji}) do
    user_id = conn.assigns[:current_user_id]
    case MessageService.MessageManager.add_reaction(message_id, user_id, emoji) do
      {:ok, message} -> json(conn, %{success: true, data: message})
      {:error, reason} -> conn |> put_status(400) |> json(%{success: false, error: reason})
    end
  end

  operation :remove_reaction,
    summary: "Remove a reaction from a message",
    description: "Remove your emoji reaction from a message",
    parameters: [
      message_id: [
        in: :path,
        type: :string,
        required: true,
        description: "The message ID",
        example: "msg_abc123def456"
      ],
      emoji: [
        in: :path,
        type: :string,
        required: true,
        description: "The emoji identifier to remove",
        example: "thumbs_up"
      ]
    ],
    responses: [
      ok: {"Reaction removed successfully", "application/json", Message.MessageResponse},
      bad_request: {"Invalid request", "application/json", Common.ErrorResponse},
      unauthorized: {"Unauthorized", "application/json", Common.ErrorResponse}
    ]

  def remove_reaction(conn, %{"message_id" => message_id, "emoji" => emoji}) do
    user_id = conn.assigns[:current_user_id]
    case MessageService.MessageManager.remove_reaction(message_id, user_id, emoji) do
      {:ok, message} -> json(conn, %{success: true, data: message})
      {:error, reason} -> conn |> put_status(400) |> json(%{success: false, error: reason})
    end
  end

  operation :mark_read,
    summary: "Mark messages as read",
    description: "Mark one or more messages as read in a conversation",
    parameters: [
      conversation_id: [
        in: :path,
        type: :string,
        required: true,
        description: "The conversation ID",
        example: "conv_xyz789"
      ]
    ],
    request_body: {"Message IDs to mark as read", "application/json", Message.MarkReadRequest},
    responses: [
      ok: {"Messages marked as read", "application/json", Common.SuccessResponse},
      unauthorized: {"Unauthorized", "application/json", Common.ErrorResponse}
    ]

  def mark_read(conn, %{"conversation_id" => conv_id, "message_ids" => message_ids}) do
    user_id = conn.assigns[:current_user_id]
    MessageService.MessageManager.mark_as_read(conv_id, user_id, message_ids)
    json(conn, %{success: true})
  end

  operation :mark_delivered,
    summary: "Mark messages as delivered",
    description: "Mark one or more messages as delivered in a conversation",
    parameters: [
      conversation_id: [
        in: :path,
        type: :string,
        required: true,
        description: "The conversation ID",
        example: "conv_xyz789"
      ]
    ],
    request_body: {"Message IDs to mark as delivered", "application/json", Message.MarkDeliveredRequest},
    responses: [
      ok: {"Messages marked as delivered", "application/json", Common.SuccessResponse},
      unauthorized: {"Unauthorized", "application/json", Common.ErrorResponse}
    ]

  def mark_delivered(conn, %{"conversation_id" => conv_id, "message_ids" => message_ids}) do
    user_id = conn.assigns[:current_user_id]
    MessageService.MessageManager.mark_as_delivered(conv_id, user_id, message_ids)
    json(conn, %{success: true})
  end

  operation :search,
    summary: "Search messages in a conversation",
    description: "Search for messages within a conversation using a query string",
    parameters: [
      conversation_id: [
        in: :path,
        type: :string,
        required: true,
        description: "The conversation ID",
        example: "conv_xyz789"
      ],
      q: [
        in: :query,
        type: :string,
        required: true,
        description: "Search query string",
        example: "meeting tomorrow"
      ],
      limit: [
        in: :query,
        type: :integer,
        required: false,
        description: "Maximum number of results to return",
        example: 20
      ]
    ],
    responses: [
      ok: {"Search results", "application/json", Message.MessageListResponse},
      unauthorized: {"Unauthorized", "application/json", Common.ErrorResponse}
    ]

  def search(conn, %{"conversation_id" => conv_id, "q" => query} = params) do
    limit = String.to_integer(Map.get(params, "limit", "20"))
    {:ok, messages} = MessageService.MessageManager.search_messages(conv_id, query, limit: limit)
    json(conn, %{success: true, data: messages})
  end
end
