defmodule MessageService.Workers.JobSupervisor do
  @moduledoc """
  Supervisor for background job processing.

  Uses simple Task-based processing instead of Honeydew queues
  for compatibility and simplicity.
  """
  use Supervisor

  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # Task supervisor for async job execution
      {Task.Supervisor, name: MessageService.Workers.TaskSupervisor}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Enqueue a message delivery retry job.
  """
  def enqueue_delivery_retry(message_id, recipient_id, attempt \\ 1) do
    Task.Supervisor.start_child(
      MessageService.Workers.TaskSupervisor,
      fn ->
        MessageService.Workers.MessageDeliveryWorker.retry_delivery(%{
          message_id: message_id,
          recipient_id: recipient_id,
          attempt: attempt
        })
      end
    )
  end

  @doc """
  Enqueue batch read receipts for processing.
  """
  def enqueue_read_receipts(receipts) when is_list(receipts) do
    Task.Supervisor.start_child(
      MessageService.Workers.TaskSupervisor,
      fn ->
        MessageService.Workers.MessageDeliveryWorker.process_read_receipts(%{
          receipts: receipts
        })
      end
    )
  end

  @doc """
  Enqueue a message cleanup job.
  """
  def enqueue_cleanup(conversation_id, threshold_days \\ 30) do
    Task.Supervisor.start_child(
      MessageService.Workers.TaskSupervisor,
      fn ->
        MessageService.Workers.MessageDeliveryWorker.cleanup_expired_messages(%{
          conversation_id: conversation_id,
          threshold_days: threshold_days
        })
      end
    )
  end

  @doc """
  Get queue status for monitoring.
  """
  def queue_status do
    task_count = Task.Supervisor.children(MessageService.Workers.TaskSupervisor) |> length()
    %{
      active_tasks: task_count,
      status: :running
    }
  end
end
