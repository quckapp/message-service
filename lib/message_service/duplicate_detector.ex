defmodule MessageService.DuplicateDetector do
  @moduledoc """
  Bloom filter-based duplicate message detection using bloomex.

  Provides fast duplicate detection before database writes:
  - Check if message ID was recently processed
  - Detect duplicate content within conversation
  - Prevent duplicate reactions/receipts

  ## Why Bloom Filters:
  - O(1) lookup instead of database query
  - Memory efficient for high-volume message processing
  - No false negatives: if we say "not duplicate", it definitely isn't
  - Acceptable false positives (~1%): occasionally reject a unique message

  ## Usage:

      # Check before processing
      if DuplicateDetector.maybe_duplicate?(message_id) do
        # Verify with database
      else
        # Definitely new, process
      end

      # Add processed message
      DuplicateDetector.add(message_id)

      # Check content hash for duplicate content
      DuplicateDetector.maybe_duplicate_content?(conversation_id, content)
  """

  use GenServer
  require Logger

  @capacity 100_000        # Expected unique messages in window
  @error_rate 0.01         # 1% false positive rate
  @rotation_interval 3600_000  # 1 hour - rotate filters
  @filter_count 2          # Number of time-based filters (current + previous)

  defstruct [
    :message_filters,      # [current_filter, previous_filter]
    :content_filters,      # conversation_id => filter
    :reaction_filters,     # message_id => filter
    :stats,
    :timer_ref,
    :current_rotation
  ]

  # ============================================================================
  # Public API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Check if a message ID might be a duplicate.
  Returns true if possibly seen before (might be false positive).
  Returns false if definitely NOT seen before.
  """
  def maybe_duplicate?(message_id) do
    GenServer.call(__MODULE__, {:check_message, message_id})
  catch
    :exit, _ -> false  # On timeout, assume not duplicate
  end

  @doc """
  Add a message ID to the duplicate filter.
  Call after successfully processing a message.
  """
  def add(message_id) do
    GenServer.cast(__MODULE__, {:add_message, message_id})
  end

  @doc """
  Check if message content might be a duplicate in a conversation.
  Uses content hash for comparison.
  """
  def maybe_duplicate_content?(conversation_id, content) do
    content_hash = hash_content(content)
    GenServer.call(__MODULE__, {:check_content, conversation_id, content_hash})
  catch
    :exit, _ -> false
  end

  @doc """
  Add content hash to conversation filter.
  """
  def add_content(conversation_id, content) do
    content_hash = hash_content(content)
    GenServer.cast(__MODULE__, {:add_content, conversation_id, content_hash})
  end

  @doc """
  Check if a reaction might be duplicate.
  """
  def maybe_duplicate_reaction?(message_id, user_id, emoji) do
    reaction_key = "#{user_id}:#{emoji}"
    GenServer.call(__MODULE__, {:check_reaction, message_id, reaction_key})
  catch
    :exit, _ -> false
  end

  @doc """
  Add a reaction to the filter.
  """
  def add_reaction(message_id, user_id, emoji) do
    reaction_key = "#{user_id}:#{emoji}"
    GenServer.cast(__MODULE__, {:add_reaction, message_id, reaction_key})
  end

  @doc """
  Check and add atomically - returns true if was duplicate.
  """
  def check_and_add(message_id) do
    GenServer.call(__MODULE__, {:check_and_add, message_id})
  catch
    :exit, _ -> false
  end

  @doc """
  Get statistics.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  catch
    :exit, _ -> %{}
  end

  @doc """
  Force rotation of message filters.
  """
  def rotate do
    GenServer.cast(__MODULE__, :rotate)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    # Create initial filters
    # Bloomex.scalable(capacity, error, error_ratio, growth)
    # error_ratio: 0.1 means each subsequent filter has 10% of original error rate
    # growth: 2 means capacity doubles with each new filter
    current_filter = Bloomex.scalable(@capacity, @error_rate, 0.1, 2)
    previous_filter = Bloomex.scalable(@capacity, @error_rate, 0.1, 2)

    # Schedule rotation
    timer_ref = Process.send_after(self(), :rotate, @rotation_interval)

    state = %__MODULE__{
      message_filters: [current_filter, previous_filter],
      content_filters: %{},
      reaction_filters: %{},
      stats: %{
        checks: 0,
        duplicates_detected: 0,
        messages_added: 0,
        rotations: 0
      },
      timer_ref: timer_ref,
      current_rotation: DateTime.utc_now()
    }

    Logger.info("[DuplicateDetector] Started with capacity #{@capacity}, error rate #{@error_rate}")

    {:ok, state}
  end

  @impl true
  def handle_call({:check_message, message_id}, _from, state) do
    [current, previous] = state.message_filters
    key = to_string(message_id)

    # Check both filters (current and previous window)
    is_duplicate = Bloomex.member?(current, key) or Bloomex.member?(previous, key)

    new_stats = %{state.stats |
      checks: state.stats.checks + 1,
      duplicates_detected: state.stats.duplicates_detected + (if is_duplicate, do: 1, else: 0)
    }

    {:reply, is_duplicate, %{state | stats: new_stats}}
  end

  @impl true
  def handle_call({:check_content, conversation_id, content_hash}, _from, state) do
    case Map.get(state.content_filters, conversation_id) do
      nil -> {:reply, false, state}
      filter -> {:reply, Bloomex.member?(filter, content_hash), state}
    end
  end

  @impl true
  def handle_call({:check_reaction, message_id, reaction_key}, _from, state) do
    case Map.get(state.reaction_filters, message_id) do
      nil -> {:reply, false, state}
      filter -> {:reply, Bloomex.member?(filter, reaction_key), state}
    end
  end

  @impl true
  def handle_call({:check_and_add, message_id}, _from, state) do
    [current, previous] = state.message_filters
    key = to_string(message_id)

    # Check if duplicate
    is_duplicate = Bloomex.member?(current, key) or Bloomex.member?(previous, key)

    # Add to current filter
    updated_current = Bloomex.add(current, key)

    new_stats = %{state.stats |
      checks: state.stats.checks + 1,
      duplicates_detected: state.stats.duplicates_detected + (if is_duplicate, do: 1, else: 0),
      messages_added: state.stats.messages_added + (if is_duplicate, do: 0, else: 1)
    }

    {:reply, is_duplicate, %{state |
      message_filters: [updated_current, previous],
      stats: new_stats
    }}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = Map.merge(state.stats, %{
      content_filter_count: map_size(state.content_filters),
      reaction_filter_count: map_size(state.reaction_filters),
      current_rotation: state.current_rotation,
      capacity: @capacity,
      error_rate: @error_rate,
      filter_count: @filter_count
    })
    {:reply, stats, state}
  end

  @impl true
  def handle_cast({:add_message, message_id}, state) do
    [current | rest] = state.message_filters
    key = to_string(message_id)
    updated_current = Bloomex.add(current, key)

    new_stats = %{state.stats | messages_added: state.stats.messages_added + 1}

    {:noreply, %{state |
      message_filters: [updated_current | rest],
      stats: new_stats
    }}
  end

  @impl true
  def handle_cast({:add_content, conversation_id, content_hash}, state) do
    filter = get_or_create_content_filter(state.content_filters, conversation_id)
    updated_filter = Bloomex.add(filter, content_hash)
    new_filters = Map.put(state.content_filters, conversation_id, updated_filter)

    {:noreply, %{state | content_filters: new_filters}}
  end

  @impl true
  def handle_cast({:add_reaction, message_id, reaction_key}, state) do
    filter = get_or_create_reaction_filter(state.reaction_filters, message_id)
    updated_filter = Bloomex.add(filter, reaction_key)
    new_filters = Map.put(state.reaction_filters, message_id, updated_filter)

    {:noreply, %{state | reaction_filters: new_filters}}
  end

  @impl true
  def handle_cast(:rotate, state) do
    {:noreply, do_rotate(state)}
  end

  @impl true
  def handle_info(:rotate, state) do
    new_state = do_rotate(state)

    # Schedule next rotation
    timer_ref = Process.send_after(self(), :rotate, @rotation_interval)

    {:noreply, %{new_state | timer_ref: timer_ref}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp do_rotate(state) do
    # Create new current filter, previous becomes old current
    new_filter = Bloomex.scalable(@capacity, @error_rate, 0.1, 2)
    [current | _] = state.message_filters

    Logger.info("[DuplicateDetector] Rotating filters, messages in window: #{state.stats.messages_added}")

    %{state |
      message_filters: [new_filter, current],
      current_rotation: DateTime.utc_now(),
      stats: %{state.stats | rotations: state.stats.rotations + 1, messages_added: 0}
    }
  end

  defp get_or_create_content_filter(filters, key) do
    case Map.get(filters, key) do
      nil -> Bloomex.scalable(1000, @error_rate, 0.1, 2)
      filter -> filter
    end
  end

  defp get_or_create_reaction_filter(filters, key) do
    case Map.get(filters, key) do
      nil -> Bloomex.scalable(100, @error_rate, 0.1, 2)
      filter -> filter
    end
  end

  defp hash_content(content) when is_binary(content) do
    :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
  end

  defp hash_content(content) when is_map(content) do
    content
    |> Jason.encode!()
    |> hash_content()
  end

  defp hash_content(content) do
    content
    |> inspect()
    |> hash_content()
  end
end
