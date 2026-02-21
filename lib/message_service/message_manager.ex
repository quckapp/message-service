defmodule MessageService.MessageManager do
  @moduledoc "Manages message lifecycle: send, edit, delete, reactions, read receipts"
  use GenServer
  require Logger

  alias Phoenix.PubSub

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_), do: {:ok, %{}}

  # Public API

  def send_message(conversation_id, user_id, type, content, opts \\ []) do
    GenServer.call(__MODULE__, {:send, conversation_id, user_id, type, content, opts})
  end

  def get_messages(conversation_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    before_id = Keyword.get(opts, :before)
    after_id = Keyword.get(opts, :after)

    query = %{"conversation_id" => conversation_id, "deleted" => %{"$ne" => true}}
    query = if before_id, do: Map.put(query, "_id", %{"$lt" => before_id}), else: query
    query = if after_id, do: Map.put(query, "_id", %{"$gt" => after_id}), else: query

    messages =
      Mongo.find(:message_mongo, "messages", query,
        sort: %{"created_at" => -1},
        limit: limit
      )
      |> Enum.to_list()

    {:ok, messages}
  end

  def get_message(message_id) do
    case Mongo.find_one(:message_mongo, "messages", %{"_id" => message_id}) do
      nil -> {:ok, nil}
      message -> {:ok, message}
    end
  end

  def edit_message(message_id, user_id, content) do
    GenServer.call(__MODULE__, {:edit, message_id, user_id, content})
  end

  def delete_message(message_id, user_id, for_everyone \\ false) do
    GenServer.call(__MODULE__, {:delete, message_id, user_id, for_everyone})
  end

  def add_reaction(message_id, user_id, emoji) do
    GenServer.call(__MODULE__, {:add_reaction, message_id, user_id, emoji})
  end

  def remove_reaction(message_id, user_id, emoji) do
    GenServer.call(__MODULE__, {:remove_reaction, message_id, user_id, emoji})
  end

  def mark_as_read(conversation_id, user_id, message_ids) do
    GenServer.cast(__MODULE__, {:mark_read, conversation_id, user_id, message_ids})
  end

  def mark_as_delivered(conversation_id, user_id, message_ids) do
    GenServer.cast(__MODULE__, {:mark_delivered, conversation_id, user_id, message_ids})
  end

  def search_messages(conversation_id, query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    results =
      Mongo.find(:message_mongo, "messages", %{
        "conversation_id" => conversation_id,
        "deleted" => %{"$ne" => true},
        "$text" => %{"$search" => query}
      },
        sort: %{"score" => %{"$meta" => "textScore"}},
        limit: limit
      )
      |> Enum.to_list()

    {:ok, results}
  end

  # GenServer callbacks

  @impl true
  def handle_call({:send, conversation_id, user_id, type, content, opts}, _from, state) do
    message_id = UUID.uuid4()
    now = DateTime.utc_now()

    message = %{
      "_id" => message_id,
      "conversation_id" => conversation_id,
      "sender_id" => user_id,
      "type" => Atom.to_string(type),
      "content" => content,
      "attachments" => Keyword.get(opts, :attachments, []),
      "reply_to" => Keyword.get(opts, :reply_to),
      "mentions" => Keyword.get(opts, :mentions, []),
      "reactions" => [],
      "read_by" => [],
      "delivered_to" => [],
      "edited" => false,
      "deleted" => false,
      "created_at" => now,
      "updated_at" => now
    }

    case Mongo.insert_one(:message_mongo, "messages", message) do
      {:ok, _} ->
        # Cache in Redis
        cache_message(message)
        broadcast_message_event(conversation_id, :new_message, message)
        :telemetry.execute([:message, :sent], %{count: 1}, %{type: type})
        {:reply, {:ok, message}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:edit, message_id, user_id, content}, _from, state) do
    case Mongo.find_one(:message_mongo, "messages", %{"_id" => message_id}) do
      nil ->
        {:reply, {:error, "Message not found"}, state}

      %{"sender_id" => ^user_id} = message ->
        now = DateTime.utc_now()

        Mongo.update_one(:message_mongo, "messages", %{"_id" => message_id}, %{
          "$set" => %{
            "content" => content,
            "edited" => true,
            "edited_at" => now,
            "updated_at" => now
          },
          "$push" => %{
            "edit_history" => %{
              "content" => message["content"],
              "edited_at" => now
            }
          }
        })

        updated = Mongo.find_one(:message_mongo, "messages", %{"_id" => message_id})

        broadcast_message_event(message["conversation_id"], :message_edited, %{
          message_id: message_id,
          content: content
        })

        {:reply, {:ok, updated}, state}

      _ ->
        {:reply, {:error, "Not authorized to edit this message"}, state}
    end
  end

  @impl true
  def handle_call({:delete, message_id, user_id, for_everyone}, _from, state) do
    case Mongo.find_one(:message_mongo, "messages", %{"_id" => message_id}) do
      nil ->
        {:reply, {:error, "Message not found"}, state}

      %{"sender_id" => ^user_id} = message when for_everyone ->
        Mongo.update_one(:message_mongo, "messages", %{"_id" => message_id}, %{
          "$set" => %{"deleted" => true, "deleted_at" => DateTime.utc_now(), "deleted_by" => user_id}
        })

        broadcast_message_event(message["conversation_id"], :message_deleted, %{
          message_id: message_id,
          for_everyone: true
        })

        {:reply, {:ok, %{message_id: message_id, deleted: true}}, state}

      %{"sender_id" => ^user_id} ->
        Mongo.update_one(:message_mongo, "messages", %{"_id" => message_id}, %{
          "$set" => %{"deleted_for" => [user_id], "updated_at" => DateTime.utc_now()}
        })

        {:reply, {:ok, %{message_id: message_id, deleted: true}}, state}

      _ ->
        {:reply, {:error, "Not authorized to delete this message"}, state}
    end
  end

  @impl true
  def handle_call({:add_reaction, message_id, user_id, emoji}, _from, state) do
    Mongo.update_one(:message_mongo, "messages", %{"_id" => message_id}, %{
      "$push" => %{
        "reactions" => %{"user_id" => user_id, "emoji" => emoji, "created_at" => DateTime.utc_now()}
      }
    })

    message = Mongo.find_one(:message_mongo, "messages", %{"_id" => message_id})

    if message do
      broadcast_message_event(message["conversation_id"], :reaction_added, %{
        message_id: message_id,
        user_id: user_id,
        emoji: emoji
      })
    end

    {:reply, {:ok, message}, state}
  end

  @impl true
  def handle_call({:remove_reaction, message_id, user_id, emoji}, _from, state) do
    Mongo.update_one(:message_mongo, "messages", %{"_id" => message_id}, %{
      "$pull" => %{"reactions" => %{"user_id" => user_id, "emoji" => emoji}}
    })

    message = Mongo.find_one(:message_mongo, "messages", %{"_id" => message_id})

    if message do
      broadcast_message_event(message["conversation_id"], :reaction_removed, %{
        message_id: message_id,
        user_id: user_id,
        emoji: emoji
      })
    end

    {:reply, {:ok, message}, state}
  end

  @impl true
  def handle_cast({:mark_read, conversation_id, user_id, message_ids}, state) do
    Enum.each(message_ids, fn id ->
      Mongo.update_one(:message_mongo, "messages", %{"_id" => id}, %{
        "$addToSet" => %{"read_by" => %{"user_id" => user_id, "read_at" => DateTime.utc_now()}}
      })
    end)

    broadcast_message_event(conversation_id, :messages_read, %{
      user_id: user_id,
      message_ids: message_ids
    })

    {:noreply, state}
  end

  @impl true
  def handle_cast({:mark_delivered, conversation_id, user_id, message_ids}, state) do
    Enum.each(message_ids, fn id ->
      Mongo.update_one(:message_mongo, "messages", %{"_id" => id}, %{
        "$addToSet" => %{
          "delivered_to" => %{"user_id" => user_id, "delivered_at" => DateTime.utc_now()}
        }
      })
    end)

    broadcast_message_event(conversation_id, :messages_delivered, %{
      user_id: user_id,
      message_ids: message_ids
    })

    {:noreply, state}
  end

  defp broadcast_message_event(conversation_id, event, data) do
    PubSub.broadcast(
      MessageService.PubSub,
      "conversation:#{conversation_id}",
      {event, data}
    )
  end

  defp cache_message(message) do
    key = "msg:#{message["_id"]}"

    case Jason.encode(message) do
      {:ok, json} -> Redix.command(:message_redis, ["SET", key, json, "EX", "3600"])
      _ -> :ok
    end
  end
end
