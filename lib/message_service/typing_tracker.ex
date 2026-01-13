defmodule MessageService.TypingTracker do
  use GenServer
  require Logger

  @typing_timeout 5_000

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def start_typing(conversation_id, user_id) do
    GenServer.cast(__MODULE__, {:start_typing, conversation_id, user_id})
  end

  def stop_typing(conversation_id, user_id) do
    GenServer.cast(__MODULE__, {:stop_typing, conversation_id, user_id})
  end

  def get_typing_users(conversation_id) do
    GenServer.call(__MODULE__, {:get_typing, conversation_id})
  end

  @impl true
  def init(_state), do: {:ok, %{typing: %{}, timers: %{}}}

  @impl true
  def handle_cast({:start_typing, conversation_id, user_id}, state) do
    key = {conversation_id, user_id}
    
    # Cancel existing timer if any
    if timer = Map.get(state.timers, key), do: Process.cancel_timer(timer)
    
    # Set new timeout
    timer_ref = Process.send_after(self(), {:typing_timeout, key}, @typing_timeout)
    
    # Update typing users
    typing = Map.update(state.typing, conversation_id, MapSet.new([user_id]), &MapSet.put(&1, user_id))
    
    # Broadcast
    broadcast_typing(conversation_id, user_id, true)
    :telemetry.execute([:typing, :started], %{count: 1}, %{})
    
    {:noreply, %{state | typing: typing, timers: Map.put(state.timers, key, timer_ref)}}
  end

  @impl true
  def handle_cast({:stop_typing, conversation_id, user_id}, state) do
    key = {conversation_id, user_id}
    
    if timer = Map.get(state.timers, key), do: Process.cancel_timer(timer)
    
    typing = Map.update(state.typing, conversation_id, MapSet.new(), &MapSet.delete(&1, user_id))
    
    broadcast_typing(conversation_id, user_id, false)
    
    {:noreply, %{state | typing: typing, timers: Map.delete(state.timers, key)}}
  end

  @impl true
  def handle_call({:get_typing, conversation_id}, _from, state) do
    users = Map.get(state.typing, conversation_id, MapSet.new()) |> MapSet.to_list()
    {:reply, {:ok, users}, state}
  end

  @impl true
  def handle_info({:typing_timeout, {conversation_id, user_id} = key}, state) do
    typing = Map.update(state.typing, conversation_id, MapSet.new(), &MapSet.delete(&1, user_id))
    broadcast_typing(conversation_id, user_id, false)
    {:noreply, %{state | typing: typing, timers: Map.delete(state.timers, key)}}
  end

  defp broadcast_typing(conversation_id, user_id, is_typing) do
    Phoenix.PubSub.broadcast(MessageService.PubSub, "conversation:#{conversation_id}", {:typing, user_id, is_typing})
  end
end
