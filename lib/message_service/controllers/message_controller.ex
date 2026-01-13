defmodule MessageService.MessageController do
  use Phoenix.Controller, formats: [:json]

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

  def index(conn, %{"conversation_id" => conv_id} = params) do
    opts = [
      limit: String.to_integer(Map.get(params, "limit", "50")),
      before: Map.get(params, "before"),
      after: Map.get(params, "after")
    ]
    {:ok, messages} = MessageService.MessageManager.get_messages(conv_id, opts)
    json(conn, %{success: true, data: messages})
  end

  def show(conn, %{"message_id" => message_id}) do
    case MessageService.MessageManager.get_message(message_id) do
      {:ok, nil} -> conn |> put_status(404) |> json(%{success: false, error: "Message not found"})
      {:ok, message} -> json(conn, %{success: true, data: message})
    end
  end

  def edit(conn, %{"message_id" => message_id, "content" => content}) do
    user_id = conn.assigns[:current_user_id]
    case MessageService.MessageManager.edit_message(message_id, user_id, content) do
      {:ok, message} -> json(conn, %{success: true, data: message})
      {:error, reason} -> conn |> put_status(400) |> json(%{success: false, error: reason})
    end
  end

  def delete(conn, %{"message_id" => message_id} = params) do
    user_id = conn.assigns[:current_user_id]
    for_everyone = Map.get(params, "for_everyone", false)
    case MessageService.MessageManager.delete_message(message_id, user_id, for_everyone) do
      {:ok, result} -> json(conn, %{success: true, data: result})
      {:error, reason} -> conn |> put_status(400) |> json(%{success: false, error: reason})
    end
  end

  def add_reaction(conn, %{"message_id" => message_id, "emoji" => emoji}) do
    user_id = conn.assigns[:current_user_id]
    case MessageService.MessageManager.add_reaction(message_id, user_id, emoji) do
      {:ok, message} -> json(conn, %{success: true, data: message})
      {:error, reason} -> conn |> put_status(400) |> json(%{success: false, error: reason})
    end
  end

  def remove_reaction(conn, %{"message_id" => message_id, "emoji" => emoji}) do
    user_id = conn.assigns[:current_user_id]
    case MessageService.MessageManager.remove_reaction(message_id, user_id, emoji) do
      {:ok, message} -> json(conn, %{success: true, data: message})
      {:error, reason} -> conn |> put_status(400) |> json(%{success: false, error: reason})
    end
  end

  def mark_read(conn, %{"conversation_id" => conv_id, "message_ids" => message_ids}) do
    user_id = conn.assigns[:current_user_id]
    MessageService.MessageManager.mark_as_read(conv_id, user_id, message_ids)
    json(conn, %{success: true})
  end

  def mark_delivered(conn, %{"conversation_id" => conv_id, "message_ids" => message_ids}) do
    user_id = conn.assigns[:current_user_id]
    MessageService.MessageManager.mark_as_delivered(conv_id, user_id, message_ids)
    json(conn, %{success: true})
  end

  def search(conn, %{"conversation_id" => conv_id, "q" => query} = params) do
    limit = String.to_integer(Map.get(params, "limit", "20"))
    {:ok, messages} = MessageService.MessageManager.search_messages(conv_id, query, limit: limit)
    json(conn, %{success: true, data: messages})
  end
end
