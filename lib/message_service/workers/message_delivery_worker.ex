defmodule MessageService.Workers.MessageDeliveryWorker do
  @moduledoc """
  Background worker for message delivery tasks using Honeydew.

  Handles:
  - Retry failed message deliveries
  - Process message read receipts in batch
  - Clean up expired messages

  Note: Honeydew 1.5.0 workers are plain modules - no `use` macro needed.
  """

  require Logger

  alias MessageService.Kafka.Producer

  @doc """
  Retry delivering a message that failed initial delivery.
  """
  def retry_delivery(%{message_id: message_id, recipient_id: recipient_id, attempt: attempt}) do
    Logger.info("Retrying message delivery",
      message_id: message_id,
      recipient_id: recipient_id,
      attempt: attempt
    )

    case deliver_message(message_id, recipient_id) do
      :ok ->
        Logger.info("Message delivered successfully on retry",
          message_id: message_id,
          attempt: attempt
        )
        :ok

      {:error, reason} when attempt < 5 ->
        # Schedule another retry with exponential backoff
        delay = :math.pow(2, attempt) |> round() |> :timer.seconds()

        Process.send_after(self(), {:retry, %{
          message_id: message_id,
          recipient_id: recipient_id,
          attempt: attempt + 1
        }}, delay)

        {:error, :will_retry}

      {:error, reason} ->
        Logger.error("Message delivery failed after max retries",
          message_id: message_id,
          reason: inspect(reason)
        )
        {:error, :max_retries_exceeded}
    end
  end

  @doc """
  Process read receipts in batch for efficiency.
  """
  def process_read_receipts(%{receipts: receipts}) when is_list(receipts) do
    Logger.info("Processing batch read receipts", count: length(receipts))

    Enum.each(receipts, fn receipt ->
      Producer.publish_read_receipt_event(receipt)
    end)

    :ok
  end

  @doc """
  Clean up messages older than the specified threshold.
  """
  def cleanup_expired_messages(%{threshold_days: days, conversation_id: conversation_id}) do
    threshold = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60, :second)

    Logger.info("Cleaning up expired messages",
      conversation_id: conversation_id,
      threshold: threshold
    )

    # Query and delete expired messages
    case Mongo.delete_many(:message_mongo, "messages", %{
      "conversation_id" => conversation_id,
      "created_at" => %{"$lt" => threshold},
      "pinned" => %{"$ne" => true}
    }) do
      {:ok, %{deleted_count: count}} ->
        Logger.info("Cleaned up expired messages",
          conversation_id: conversation_id,
          deleted_count: count
        )
        {:ok, count}

      {:error, reason} ->
        Logger.error("Failed to cleanup messages",
          conversation_id: conversation_id,
          reason: inspect(reason)
        )
        {:error, reason}
    end
  end

  # Private functions
  defp deliver_message(message_id, recipient_id) do
    # Attempt to deliver message via Kafka event
    event = %{
      type: "message.delivery.retry",
      message_id: message_id,
      recipient_id: recipient_id,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    case Producer.publish_message_event(event) do
      :ok -> :ok
      error -> error
    end
  end
end
