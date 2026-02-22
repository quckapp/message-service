defmodule MessageService.States.MessageState do
  @moduledoc """
  Formal state machine for message lifecycle using Machinery.

  ## States:
  - `:pending` - Message created but not yet sent
  - `:sent` - Message sent to server
  - `:delivered` - Message delivered to recipient device
  - `:read` - Message read by recipient
  - `:failed` - Message delivery failed

  ## Transitions:
  ```
  pending -> sent -> delivered -> read
     |         |         |
     v         v         v
   failed    failed    failed
  ```

  ## Usage:

      # Create a new message in pending state
      message = MessageState.new(attrs)

      # Transition to sent
      {:ok, message} = MessageState.send(message)

      # Transition to delivered
      {:ok, message} = MessageState.deliver(message, user_id)

      # Check current state
      MessageState.state(message)  # => :sent
  """

  use Machinery,
    states: [:pending, :sent, :delivered, :read, :failed],
    transitions: %{
      pending: [:sent, :failed],
      sent: [:delivered, :failed],
      delivered: [:read, :failed],
      read: [],
      failed: []
    }

  require Logger

  defstruct [
    :id,
    :conversation_id,
    :sender_id,
    :recipient_ids,
    :content,
    :type,
    :state,
    :created_at,
    :sent_at,
    :delivered_at,
    :read_at,
    :failed_at,
    :failure_reason,
    :metadata,
    :delivery_receipts,
    :read_receipts
  ]

  @type t :: %__MODULE__{
    id: String.t(),
    conversation_id: String.t(),
    sender_id: String.t(),
    recipient_ids: [String.t()],
    content: map() | String.t(),
    type: atom(),
    state: atom(),
    created_at: DateTime.t(),
    sent_at: DateTime.t() | nil,
    delivered_at: DateTime.t() | nil,
    read_at: DateTime.t() | nil,
    failed_at: DateTime.t() | nil,
    failure_reason: String.t() | nil,
    metadata: map(),
    delivery_receipts: map(),
    read_receipts: map()
  }

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Create a new message in pending state.
  """
  def new(attrs) do
    %__MODULE__{
      id: attrs[:id] || generate_id(),
      conversation_id: attrs[:conversation_id],
      sender_id: attrs[:sender_id],
      recipient_ids: attrs[:recipient_ids] || [],
      content: attrs[:content],
      type: attrs[:type] || :text,
      state: :pending,
      created_at: DateTime.utc_now(),
      metadata: attrs[:metadata] || %{},
      delivery_receipts: %{},
      read_receipts: %{}
    }
  end

  @doc """
  Transition message to sent state.
  """
  def send(message) do
    case Machinery.transition_to(message, :sent) do
      {:ok, updated} ->
        {:ok, %{updated | sent_at: DateTime.utc_now()}}
      error ->
        error
    end
  end

  @doc """
  Transition message to delivered state for a specific recipient.
  """
  def deliver(message, recipient_id) do
    receipts = Map.put(message.delivery_receipts, recipient_id, DateTime.utc_now())
    updated = %{message | delivery_receipts: receipts}

    # Check if all recipients have received
    all_delivered = all_recipients_delivered?(updated)

    if all_delivered and message.state == :sent do
      case Machinery.transition_to(updated, :delivered) do
        {:ok, delivered} ->
          {:ok, %{delivered | delivered_at: DateTime.utc_now()}}
        error ->
          error
      end
    else
      {:ok, updated}
    end
  end

  @doc """
  Transition message to read state for a specific recipient.
  """
  def mark_read(message, recipient_id) do
    receipts = Map.put(message.read_receipts, recipient_id, DateTime.utc_now())
    updated = %{message | read_receipts: receipts}

    # For one-to-one, mark as read when recipient reads
    # For groups, could require all to read
    if message.state in [:sent, :delivered] do
      case Machinery.transition_to(updated, :read) do
        {:ok, read} ->
          {:ok, %{read | read_at: DateTime.utc_now()}}
        error ->
          error
      end
    else
      {:ok, updated}
    end
  end

  @doc """
  Transition message to failed state.
  """
  def fail(message, reason) do
    case Machinery.transition_to(message, :failed) do
      {:ok, failed} ->
        {:ok, %{failed |
          failed_at: DateTime.utc_now(),
          failure_reason: reason
        }}
      error ->
        error
    end
  end

  @doc """
  Get the current state of the message.
  """
  def state(message), do: message.state

  @doc """
  Check if message can transition to a given state.
  """
  def can_transition?(message, target_state) do
    case Machinery.transition_to(message, target_state) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Check if message is in a terminal state.
  """
  def terminal?(message) do
    message.state in [:read, :failed]
  end

  @doc """
  Get delivery status summary.
  """
  def delivery_summary(message) do
    total = length(message.recipient_ids)
    delivered = map_size(message.delivery_receipts)
    read = map_size(message.read_receipts)

    %{
      state: message.state,
      total_recipients: total,
      delivered_count: delivered,
      read_count: read,
      pending_count: total - delivered
    }
  end

  # ============================================================================
  # Machinery Callbacks
  # ============================================================================

  @doc false
  def guard_transition(message, :pending, :sent) do
    # Validate message has content and recipients
    cond do
      is_nil(message.content) or message.content == "" ->
        {:error, "Message content cannot be empty"}
      Enum.empty?(message.recipient_ids) ->
        {:error, "Message must have at least one recipient"}
      true ->
        {:ok, message}
    end
  end

  def guard_transition(message, :sent, :delivered) do
    # Must have at least one delivery receipt
    if map_size(message.delivery_receipts) > 0 do
      {:ok, message}
    else
      {:error, "No delivery receipts recorded"}
    end
  end

  def guard_transition(message, _from, _to) do
    {:ok, message}
  end

  @doc false
  def before_transition(message, _from, to) do
    Logger.debug("[MessageState] Transitioning message #{message.id} to #{to}")
    message
  end

  @doc false
  def after_transition(message, from, to) do
    Logger.info("[MessageState] Message #{message.id} transitioned from #{from} to #{to}")

    # Emit telemetry
    :telemetry.execute(
      [:message_service, :message, :state_transition],
      %{count: 1},
      %{from: from, to: to, message_type: message.type}
    )

    message
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp all_recipients_delivered?(message) do
    delivered_ids = Map.keys(message.delivery_receipts) |> MapSet.new()
    recipient_ids = MapSet.new(message.recipient_ids)

    MapSet.subset?(recipient_ids, delivered_ids)
  end

  defp generate_id do
    "msg_" <> (:crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower))
  end
end
