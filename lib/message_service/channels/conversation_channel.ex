defmodule MessageService.ConversationChannel do
  use Phoenix.Channel
  require Logger

  @impl true
  def join("conversation:" <> conversation_id, _params, socket) do
    Phoenix.PubSub.subscribe(MessageService.PubSub, "conversation:#{conversation_id}")
    Logger.info("User #{socket.assigns.user_id} joined conversation #{conversation_id}")
    {:ok, assign(socket, :conversation_id, conversation_id)}
  end

  @impl true
  def handle_in("send_message", %{"type" => type, "content" => content} = params, socket) do
    opts = [
      attachments: Map.get(params, "attachments", []),
      reply_to: Map.get(params, "reply_to"),
      mentions: Map.get(params, "mentions", [])
    ]
    
    case MessageService.MessageManager.send_message(
      socket.assigns.conversation_id,
      socket.assigns.user_id,
      String.to_existing_atom(type),
      content,
      opts
    ) do
      {:ok, message} -> {:reply, {:ok, %{message: message}}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  @impl true
  def handle_in("typing", %{"typing" => true}, socket) do
    MessageService.TypingTracker.start_typing(socket.assigns.conversation_id, socket.assigns.user_id)
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("typing", %{"typing" => false}, socket) do
    MessageService.TypingTracker.stop_typing(socket.assigns.conversation_id, socket.assigns.user_id)
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("mark_read", %{"message_ids" => message_ids}, socket) do
    MessageService.MessageManager.mark_as_read(socket.assigns.conversation_id, socket.assigns.user_id, message_ids)
    {:reply, :ok, socket}
  end

  @impl true
  def handle_info({:new_message, message}, socket) do
    push(socket, "new_message", %{message: message})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:message_edited, message}, socket) do
    push(socket, "message_edited", %{message: message})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:message_deleted, message_id, scope}, socket) do
    push(socket, "message_deleted", %{message_id: message_id, scope: scope})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:reaction_added, message_id, user_id, emoji}, socket) do
    push(socket, "reaction_added", %{message_id: message_id, user_id: user_id, emoji: emoji})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:reaction_removed, message_id, user_id, emoji}, socket) do
    push(socket, "reaction_removed", %{message_id: message_id, user_id: user_id, emoji: emoji})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:typing, user_id, is_typing}, socket) do
    if user_id != socket.assigns.user_id do
      push(socket, "typing", %{user_id: user_id, typing: is_typing})
    end
    {:noreply, socket}
  end

  @impl true
  def handle_info({:messages_read, user_id, message_ids}, socket) do
    push(socket, "messages_read", %{user_id: user_id, message_ids: message_ids})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:messages_delivered, user_id, message_ids}, socket) do
    push(socket, "messages_delivered", %{user_id: user_id, message_ids: message_ids})
    {:noreply, socket}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}
end
