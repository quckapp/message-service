defmodule MessageService.ParallelProcessor do
  @moduledoc """
  Flow-based parallel message processor for bulk operations.

  Uses Elixir Flow library for parallel processing of message operations:
  - Bulk message delivery tracking
  - Batch read receipt processing
  - Parallel message status updates

  ## Usage:

      # Mark multiple messages as read in parallel
      ParallelProcessor.mark_many_read(message_ids, user_id)

      # Process bulk delivery confirmations
      ParallelProcessor.process_bulk_delivery(delivery_events)

  ## Configuration:

  Configure in config.exs:

      config :message_service, :parallel_processor,
        max_demand: 50,
        stages: System.schedulers_online()
  """

  require Logger

  alias MessageService.MessageManager

  @doc """
  Mark multiple messages as read in parallel.

  Returns count of successfully updated messages.
  """
  def mark_many_read(message_ids, user_id) when is_list(message_ids) do
    case length(message_ids) do
      0 ->
        {:ok, %{updated: 0, failed: 0}}

      count when count <= 20 ->
        # For small batches, process sequentially
        mark_read_sequential(message_ids, user_id)

      _ ->
        # For larger batches, use Flow
        mark_read_parallel(message_ids, user_id)
    end
  end

  @doc """
  Mark multiple messages as delivered in parallel.
  """
  def mark_many_delivered(message_ids, user_id) when is_list(message_ids) do
    case length(message_ids) do
      0 ->
        {:ok, %{updated: 0, failed: 0}}

      count when count <= 20 ->
        mark_delivered_sequential(message_ids, user_id)

      _ ->
        mark_delivered_parallel(message_ids, user_id)
    end
  end

  @doc """
  Process bulk message events in parallel.

  Useful for processing batches from Kafka.
  """
  def process_bulk_events(events) when is_list(events) do
    case length(events) do
      0 ->
        {:ok, %{processed: 0, failed: 0}}

      count when count <= 10 ->
        process_events_sequential(events)

      _ ->
        process_events_parallel(events)
    end
  end

  @doc """
  Search messages across multiple conversations in parallel.
  """
  def search_many_conversations(conversation_ids, query, opts \\ []) when is_list(conversation_ids) do
    limit_per_conversation = opts[:limit] || 10

    results =
      conversation_ids
      |> Flow.from_enumerable(max_demand: max_demand(), stages: stages())
      |> Flow.flat_map(fn conversation_id ->
        case MessageManager.search_messages(conversation_id, query, limit: limit_per_conversation) do
          {:ok, messages} -> messages
          {:error, _} -> []
        end
      end)
      |> Enum.to_list()
      |> Enum.sort_by(& &1.created_at, {:desc, DateTime})
      |> Enum.take(opts[:total_limit] || 50)

    {:ok, results}
  end

  @doc """
  Get unread counts for multiple conversations in parallel.
  """
  def get_bulk_unread_counts(conversation_ids, user_id) when is_list(conversation_ids) do
    results =
      conversation_ids
      |> Flow.from_enumerable(max_demand: max_demand(), stages: stages())
      |> Flow.map(fn conversation_id ->
        case MessageManager.get_unread_count(conversation_id, user_id) do
          {:ok, count} -> {conversation_id, count}
          {:error, _} -> {conversation_id, 0}
        end
      end)
      |> Enum.to_list()
      |> Map.new()

    {:ok, results}
  end

  # Private functions

  defp mark_read_sequential(message_ids, user_id) do
    results = Enum.map(message_ids, fn message_id ->
      case :ets.lookup(:message_store, message_id) do
        [{^message_id, message}] ->
          if message.sender_id != user_id and message.state in [:sent, :delivered] do
            updated = %{message | state: :read, updated_at: DateTime.utc_now()}
            :ets.insert(:message_store, {message_id, updated})
            :ok
          else
            :skipped
          end
        [] ->
          :not_found
      end
    end)

    updated = Enum.count(results, &(&1 == :ok))
    failed = Enum.count(results, &(&1 == :not_found))

    {:ok, %{updated: updated, failed: failed}}
  end

  defp mark_read_parallel(message_ids, user_id) do
    results =
      message_ids
      |> Flow.from_enumerable(max_demand: max_demand(), stages: stages())
      |> Flow.map(fn message_id ->
        case :ets.lookup(:message_store, message_id) do
          [{^message_id, message}] ->
            if message.sender_id != user_id and message.state in [:sent, :delivered] do
              updated = %{message | state: :read, updated_at: DateTime.utc_now()}
              :ets.insert(:message_store, {message_id, updated})
              :ok
            else
              :skipped
            end
          [] ->
            :not_found
        end
      end)
      |> Enum.to_list()

    updated = Enum.count(results, &(&1 == :ok))
    failed = Enum.count(results, &(&1 == :not_found))

    Logger.debug("[ParallelProcessor] Marked #{updated} messages as read")

    {:ok, %{updated: updated, failed: failed}}
  end

  defp mark_delivered_sequential(message_ids, user_id) do
    results = Enum.map(message_ids, fn message_id ->
      case MessageManager.mark_delivered(message_id, user_id) do
        {:ok, _} -> :ok
        {:error, _} -> :failed
      end
    end)

    updated = Enum.count(results, &(&1 == :ok))
    failed = Enum.count(results, &(&1 == :failed))

    {:ok, %{updated: updated, failed: failed}}
  end

  defp mark_delivered_parallel(message_ids, user_id) do
    results =
      message_ids
      |> Flow.from_enumerable(max_demand: max_demand(), stages: stages())
      |> Flow.map(fn message_id ->
        case MessageManager.mark_delivered(message_id, user_id) do
          {:ok, _} -> :ok
          {:error, _} -> :failed
        end
      end)
      |> Enum.to_list()

    updated = Enum.count(results, &(&1 == :ok))
    failed = Enum.count(results, &(&1 == :failed))

    {:ok, %{updated: updated, failed: failed}}
  end

  defp process_events_sequential(events) do
    results = Enum.map(events, &process_single_event/1)

    processed = Enum.count(results, &(&1 == :ok))
    failed = Enum.count(results, &(&1 == :error))

    {:ok, %{processed: processed, failed: failed}}
  end

  defp process_events_parallel(events) do
    results =
      events
      |> Flow.from_enumerable(max_demand: max_demand(), stages: stages())
      |> Flow.map(&process_single_event/1)
      |> Enum.to_list()

    processed = Enum.count(results, &(&1 == :ok))
    failed = Enum.count(results, &(&1 == :error))

    {:ok, %{processed: processed, failed: failed}}
  end

  defp process_single_event(event) do
    try do
      case event[:type] || event["type"] do
        "message.delivered" ->
          message_id = event[:message_id] || event["message_id"]
          user_id = event[:user_id] || event["user_id"]
          MessageManager.mark_delivered(message_id, user_id)
          :ok

        "message.read" ->
          conversation_id = event[:conversation_id] || event["conversation_id"]
          user_id = event[:user_id] || event["user_id"]
          message_id = event[:message_id] || event["message_id"]
          MessageManager.mark_read(conversation_id, user_id, message_id)
          :ok

        _ ->
          Logger.warning("[ParallelProcessor] Unknown event type: #{inspect(event[:type])}")
          :skipped
      end
    rescue
      e ->
        Logger.error("[ParallelProcessor] Failed to process event: #{inspect(e)}")
        :error
    end
  end

  defp max_demand do
    config()[:max_demand] || 50
  end

  defp stages do
    config()[:stages] || System.schedulers_online()
  end

  defp config do
    Application.get_env(:message_service, :parallel_processor, [])
  end
end
