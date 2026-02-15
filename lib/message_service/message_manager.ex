defmodule MessageService.MessageManager do
  @moduledoc """
  Message Manager - Manages message lifecycle and conversation state.

  ## Design Patterns Used:
  - **Repository Pattern**: Abstracts message storage
  - **Observer Pattern**: Notifies subscribers of message events
  - **CQRS**: Separates read and write operations

  ## Responsibilities:
  - Create, update, delete messages
  - Manage message delivery status
  - Handle read receipts
  - Coordinate with Kafka for event publishing
  """
  use GenServer
  require Logger

  alias MessageService.Kafka.Producer

  # Message states
  @valid_states ~w(pending sent delivered read failed)a

  # Message types
  @valid_types ~w(text image video audio file location sticker system)a

  defstruct [
    :message_count,
    :stats
  ]

  # ============================================================================
  # Public API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Send a new message"
  def send_message(sender_id, conversation_id, content, opts \\ []) do
    GenServer.call(__MODULE__, {:send_message, sender_id, conversation_id, content, opts})
  end

  @doc "Get messages for a conversation"
  def get_messages(conversation_id, opts \\ []) do
    GenServer.call(__MODULE__, {:get_messages, conversation_id, opts})
  end

  @doc "Get a single message"
  def get_message(message_id) do
    GenServer.call(__MODULE__, {:get_message, message_id})
  end

  @doc "Mark message as delivered"
  def mark_delivered(message_id, user_id) do
    GenServer.call(__MODULE__, {:mark_delivered, message_id, user_id})
  end

  @doc "Mark messages as read"
  def mark_read(conversation_id, user_id, up_to_message_id \\ nil) do
    GenServer.call(__MODULE__, {:mark_read, conversation_id, user_id, up_to_message_id})
  end

  @doc "Delete a message"
  def delete_message(message_id, user_id, delete_for_all \\ false) do
    GenServer.call(__MODULE__, {:delete_message, message_id, user_id, delete_for_all})
  end

  @doc "Edit a message"
  def edit_message(message_id, user_id, new_content) do
    GenServer.call(__MODULE__, {:edit_message, message_id, user_id, new_content})
  end

  @doc "Get unread count for user in conversation"
  def get_unread_count(conversation_id, user_id) do
    GenServer.call(__MODULE__, {:get_unread_count, conversation_id, user_id})
  end

  @doc "Get message statistics"
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @doc "Send a message (5-arity version for controller compatibility)"
  def send_message(conversation_id, sender_id, type, content, opts) when is_atom(type) do
    send_message(sender_id, conversation_id, content, Keyword.put(opts, :type, Atom.to_string(type)))
  end

  @doc "Mark messages as read (alias for mark_read)"
  def mark_as_read(conversation_id, user_id, message_ids) do
    last_message_id = if is_list(message_ids), do: List.last(message_ids), else: message_ids
    mark_read(conversation_id, user_id, last_message_id)
  end

  @doc "Mark messages as delivered (batch version)"
  def mark_as_delivered(conversation_id, user_id, message_ids) when is_list(message_ids) do
    Enum.each(message_ids, fn message_id ->
      mark_delivered(message_id, user_id)
    end)
    {:ok, %{marked_count: length(message_ids)}}
  end

  @doc "Add a reaction to a message"
  def add_reaction(message_id, user_id, emoji) do
    GenServer.call(__MODULE__, {:add_reaction, message_id, user_id, emoji})
  end

  @doc "Remove a reaction from a message"
  def remove_reaction(message_id, user_id, emoji) do
    GenServer.call(__MODULE__, {:remove_reaction, message_id, user_id, emoji})
  end

  @doc "Search messages in a conversation"
  def search_messages(conversation_id, query, opts \\ []) do
    GenServer.call(__MODULE__, {:search_messages, conversation_id, query, opts})
  end

  @doc "Process an incoming message from Kafka"
  def process_incoming_message(message_data) do
    GenServer.call(__MODULE__, {:process_incoming_message, message_data})
  end

  @doc "Update a message (from Kafka events)"
  def update_message(message_id, updates) do
    GenServer.call(__MODULE__, {:update_message, message_id, updates})
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    # Initialize ETS tables
    :ets.new(:message_store, [:set, :named_table, :public])
    :ets.new(:conversation_messages, [:bag, :named_table, :public])
    :ets.new(:message_read_receipts, [:bag, :named_table, :public])
    :ets.new(:message_stats, [:set, :named_table, :public])

    init_stats()

    state = %__MODULE__{
      message_count: 0,
      stats: %{}
    }

    Logger.info("[MessageManager] Started")
    {:ok, state}
  end

  @impl true
  def handle_call({:send_message, sender_id, conversation_id, content, opts}, _from, state) do
    with {:ok, message_type} <- validate_message_type(opts[:type] || "text") do
      message_id = generate_message_id()

      message = %{
        id: message_id,
        conversation_id: conversation_id,
        sender_id: sender_id,
        content: content,
        type: message_type,
        state: :sent,
        created_at: DateTime.utc_now(),
        updated_at: nil,
        edited_at: nil,
        deleted_at: nil,
        metadata: opts[:metadata] || %{},
        reply_to: opts[:reply_to],
        mentions: opts[:mentions] || []
      }

      # Store message
      :ets.insert(:message_store, {message_id, message})
      :ets.insert(:conversation_messages, {conversation_id, message_id})

      # Publish event
      publish_message_event("message.created", message)

      increment_stat(:messages_sent)

      {:reply, {:ok, message}, %{state | message_count: state.message_count + 1}}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_messages, conversation_id, opts}, _from, state) do
    limit = opts[:limit] || 50
    before_id = opts[:before]
    after_id = opts[:after]

    message_ids = :ets.lookup(:conversation_messages, conversation_id)
                  |> Enum.map(fn {_, id} -> id end)

    messages = message_ids
               |> Enum.map(&get_message_from_ets/1)
               |> Enum.filter(&match?({:ok, _}, &1))
               |> Enum.map(fn {:ok, msg} -> msg end)
               |> Enum.filter(fn msg -> is_nil(msg.deleted_at) end)
               |> Enum.sort_by(& &1.created_at, {:desc, DateTime})
               |> apply_cursor_filter(before_id, after_id)
               |> Enum.take(limit)

    {:reply, {:ok, messages}, state}
  end

  @impl true
  def handle_call({:get_message, message_id}, _from, state) do
    result = get_message_from_ets(message_id)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:mark_delivered, message_id, user_id}, _from, state) do
    case get_message_from_ets(message_id) do
      {:ok, message} ->
        if message.state == :sent do
          updated_message = %{message |
            state: :delivered,
            updated_at: DateTime.utc_now()
          }

          :ets.insert(:message_store, {message_id, updated_message})

          # Record delivery receipt
          receipt = %{
            message_id: message_id,
            user_id: user_id,
            type: :delivered,
            at: DateTime.utc_now()
          }
          :ets.insert(:message_read_receipts, {message_id, receipt})

          publish_message_event("message.delivered", updated_message)
          increment_stat(:messages_delivered)

          {:reply, {:ok, updated_message}, state}
        else
          {:reply, {:ok, message}, state}
        end

      {:error, :not_found} ->
        {:reply, {:error, :message_not_found}, state}
    end
  end

  @impl true
  def handle_call({:mark_read, conversation_id, user_id, up_to_message_id}, _from, state) do
    message_ids = :ets.lookup(:conversation_messages, conversation_id)
                  |> Enum.map(fn {_, id} -> id end)

    read_count = Enum.reduce(message_ids, 0, fn message_id, count ->
      case get_message_from_ets(message_id) do
        {:ok, message} ->
          should_mark = message.sender_id != user_id and
                       message.state in [:sent, :delivered] and
                       (is_nil(up_to_message_id) or message_id <= up_to_message_id)

          if should_mark do
            updated_message = %{message | state: :read, updated_at: DateTime.utc_now()}
            :ets.insert(:message_store, {message_id, updated_message})

            receipt = %{
              message_id: message_id,
              user_id: user_id,
              type: :read,
              at: DateTime.utc_now()
            }
            :ets.insert(:message_read_receipts, {message_id, receipt})

            count + 1
          else
            count
          end

        _ ->
          count
      end
    end)

    if read_count > 0 do
      publish_read_receipt_event(conversation_id, user_id, read_count)
      :ets.update_counter(:message_stats, :messages_read, read_count)
    end

    {:reply, {:ok, %{read_count: read_count}}, state}
  end

  @impl true
  def handle_call({:delete_message, message_id, user_id, delete_for_all}, _from, state) do
    case get_message_from_ets(message_id) do
      {:ok, message} ->
        if message.sender_id == user_id or not delete_for_all do
          updated_message = %{message |
            deleted_at: DateTime.utc_now(),
            content: if(delete_for_all, do: nil, else: message.content),
            metadata: Map.put(message.metadata, :deleted_for_all, delete_for_all)
          }

          :ets.insert(:message_store, {message_id, updated_message})

          publish_message_event("message.deleted", updated_message)
          increment_stat(:messages_deleted)

          {:reply, {:ok, updated_message}, state}
        else
          {:reply, {:error, :unauthorized}, state}
        end

      {:error, :not_found} ->
        {:reply, {:error, :message_not_found}, state}
    end
  end

  @impl true
  def handle_call({:edit_message, message_id, user_id, new_content}, _from, state) do
    case get_message_from_ets(message_id) do
      {:ok, message} ->
        if message.sender_id == user_id and is_nil(message.deleted_at) do
          updated_message = %{message |
            content: new_content,
            edited_at: DateTime.utc_now(),
            updated_at: DateTime.utc_now(),
            metadata: Map.put(message.metadata, :original_content, message.content)
          }

          :ets.insert(:message_store, {message_id, updated_message})

          publish_message_event("message.edited", updated_message)
          increment_stat(:messages_edited)

          {:reply, {:ok, updated_message}, state}
        else
          {:reply, {:error, :unauthorized}, state}
        end

      {:error, :not_found} ->
        {:reply, {:error, :message_not_found}, state}
    end
  end

  @impl true
  def handle_call({:get_unread_count, conversation_id, user_id}, _from, state) do
    message_ids = :ets.lookup(:conversation_messages, conversation_id)
                  |> Enum.map(fn {_, id} -> id end)

    unread_count = Enum.count(message_ids, fn message_id ->
      case get_message_from_ets(message_id) do
        {:ok, message} ->
          message.sender_id != user_id and
          message.state in [:sent, :delivered] and
          is_nil(message.deleted_at)
        _ ->
          false
      end
    end)

    {:reply, {:ok, unread_count}, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      messages_sent: get_stat(:messages_sent),
      messages_delivered: get_stat(:messages_delivered),
      messages_read: get_stat(:messages_read),
      messages_edited: get_stat(:messages_edited),
      messages_deleted: get_stat(:messages_deleted),
      total_messages: :ets.info(:message_store, :size)
    }
    {:reply, stats, state}
  end

  @impl true
  def handle_call({:add_reaction, message_id, user_id, emoji}, _from, state) do
    case get_message_from_ets(message_id) do
      {:ok, message} ->
        reactions = Map.get(message, :reactions, %{})
        emoji_users = Map.get(reactions, emoji, [])

        updated_reactions = if user_id in emoji_users do
          reactions
        else
          Map.put(reactions, emoji, [user_id | emoji_users])
        end

        updated_message = Map.put(message, :reactions, updated_reactions)
        :ets.insert(:message_store, {message_id, updated_message})

        publish_message_event("message.reaction_added", updated_message)
        {:reply, {:ok, updated_message}, state}

      {:error, :not_found} ->
        {:reply, {:error, :message_not_found}, state}
    end
  end

  @impl true
  def handle_call({:remove_reaction, message_id, user_id, emoji}, _from, state) do
    case get_message_from_ets(message_id) do
      {:ok, message} ->
        reactions = Map.get(message, :reactions, %{})
        emoji_users = Map.get(reactions, emoji, [])

        updated_reactions = Map.put(reactions, emoji, Enum.reject(emoji_users, &(&1 == user_id)))
        updated_message = Map.put(message, :reactions, updated_reactions)
        :ets.insert(:message_store, {message_id, updated_message})

        publish_message_event("message.reaction_removed", updated_message)
        {:reply, {:ok, updated_message}, state}

      {:error, :not_found} ->
        {:reply, {:error, :message_not_found}, state}
    end
  end

  @impl true
  def handle_call({:search_messages, conversation_id, query, opts}, _from, state) do
    limit = opts[:limit] || 20
    query_lower = String.downcase(query)

    message_ids = :ets.lookup(:conversation_messages, conversation_id)
                  |> Enum.map(fn {_, id} -> id end)

    messages = message_ids
               |> Enum.map(&get_message_from_ets/1)
               |> Enum.filter(&match?({:ok, _}, &1))
               |> Enum.map(fn {:ok, msg} -> msg end)
               |> Enum.filter(fn msg ->
                 is_nil(msg.deleted_at) and
                 is_binary(msg.content) and
                 String.contains?(String.downcase(msg.content), query_lower)
               end)
               |> Enum.sort_by(& &1.created_at, {:desc, DateTime})
               |> Enum.take(limit)

    {:reply, {:ok, messages}, state}
  end

  @impl true
  def handle_call({:process_incoming_message, message_data}, _from, state) do
    message_id = message_data[:id] || generate_message_id()

    message = %{
      id: message_id,
      conversation_id: message_data[:conversation_id],
      sender_id: message_data[:sender_id],
      content: message_data[:content],
      type: message_data[:type] || :text,
      state: :sent,
      created_at: message_data[:timestamp] || DateTime.utc_now(),
      updated_at: nil,
      edited_at: nil,
      deleted_at: nil,
      metadata: message_data[:metadata] || %{},
      reply_to: nil,
      mentions: []
    }

    :ets.insert(:message_store, {message_id, message})
    :ets.insert(:conversation_messages, {message_data[:conversation_id], message_id})

    increment_stat(:messages_sent)

    {:reply, {:ok, message}, %{state | message_count: state.message_count + 1}}
  end

  @impl true
  def handle_call({:update_message, message_id, updates}, _from, state) do
    case get_message_from_ets(message_id) do
      {:ok, message} ->
        updated_message = message
        |> maybe_update(:content, updates[:content])
        |> maybe_update(:edited_at, updates[:edited_at])
        |> Map.put(:updated_at, DateTime.utc_now())

        :ets.insert(:message_store, {message_id, updated_message})
        publish_message_event("message.updated", updated_message)

        {:reply, {:ok, updated_message}, state}

      {:error, :not_found} ->
        {:reply, {:error, :message_not_found}, state}
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp generate_message_id do
    "msg_" <> (:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower))
  end

  defp validate_message_type(type) when type in ["text", "image", "video", "audio", "file", "location", "sticker", "system"] do
    {:ok, String.to_atom(type)}
  end
  defp validate_message_type(type) when type in @valid_types do
    {:ok, type}
  end
  defp validate_message_type(_), do: {:error, :invalid_message_type}

  defp get_message_from_ets(message_id) do
    case :ets.lookup(:message_store, message_id) do
      [{^message_id, message}] -> {:ok, message}
      [] -> {:error, :not_found}
    end
  end

  defp apply_cursor_filter(messages, nil, nil), do: messages
  defp apply_cursor_filter(messages, before_id, nil) do
    Enum.drop_while(messages, fn msg -> msg.id != before_id end) |> Enum.drop(1)
  end
  defp apply_cursor_filter(messages, nil, after_id) do
    Enum.take_while(messages, fn msg -> msg.id != after_id end)
  end
  defp apply_cursor_filter(messages, _before_id, _after_id), do: messages

  defp publish_message_event(event_type, message) do
    event = %{
      event_type: event_type,
      message_id: message.id,
      conversation_id: message.conversation_id,
      sender_id: message.sender_id,
      type: message.type,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    Producer.publish_message_event(event)
  rescue
    _ -> :ok
  end

  defp publish_read_receipt_event(conversation_id, user_id, count) do
    event = %{
      event_type: "messages.read",
      conversation_id: conversation_id,
      user_id: user_id,
      count: count,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    Producer.publish_read_receipt_event(event)
  rescue
    _ -> :ok
  end

  defp init_stats do
    :ets.insert(:message_stats, {:messages_sent, 0})
    :ets.insert(:message_stats, {:messages_delivered, 0})
    :ets.insert(:message_stats, {:messages_read, 0})
    :ets.insert(:message_stats, {:messages_edited, 0})
    :ets.insert(:message_stats, {:messages_deleted, 0})
  end

  defp get_stat(key) do
    case :ets.lookup(:message_stats, key) do
      [{^key, value}] -> value
      [] -> 0
    end
  end

  defp increment_stat(key) do
    :ets.update_counter(:message_stats, key, 1)
  rescue
    _ -> :ok
  end

  defp maybe_update(map, _key, nil), do: map
  defp maybe_update(map, key, value), do: Map.put(map, key, value)
end
