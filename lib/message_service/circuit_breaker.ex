defmodule MessageService.CircuitBreaker do
  @moduledoc """
  Circuit breaker wrapper using the fuse library.

  Provides fault tolerance for external service calls (Redis, MongoDB, HTTP, Kafka).
  When a service fails repeatedly, the circuit opens and fails fast,
  preventing cascade failures and allowing the service to recover.

  ## Usage:

      CircuitBreaker.call(:redis, fn ->
        RedisClient.get(key)
      end)

      CircuitBreaker.call(:kafka, fn ->
        Producer.publish(event)
      end, default: {:error, :kafka_unavailable})
  """

  require Logger

  @fuses %{
    redis: :message_redis_fuse,
    mongodb: :message_mongodb_fuse,
    http: :message_http_fuse,
    kafka: :message_kafka_fuse
  }

  @doc """
  Initialize all circuit breakers. Call this from Application.start/2.
  """
  def init do
    Enum.each(@fuses, fn {name, fuse_name} ->
      opts = fuse_options(name)
      :fuse.install(fuse_name, opts)
      Logger.info("[CircuitBreaker] Installed fuse #{fuse_name}")
    end)
    :ok
  end

  @doc """
  Execute a function with circuit breaker protection.
  """
  def call(service, fun, opts \\ []) do
    fuse_name = Map.get(@fuses, service, service)

    case :fuse.ask(fuse_name, :sync) do
      :ok ->
        try do
          result = fun.()
          :fuse.melt(fuse_name)
          result
        rescue
          e ->
            :fuse.melt(fuse_name)
            Logger.error("[CircuitBreaker] #{service} call failed: #{inspect(e)}")
            handle_error(service, opts, e)
        catch
          :exit, reason ->
            :fuse.melt(fuse_name)
            Logger.error("[CircuitBreaker] #{service} call exited: #{inspect(reason)}")
            handle_error(service, opts, reason)
        end

      :blown ->
        Logger.warning("[CircuitBreaker] #{service} circuit is open, failing fast")
        if on_open = opts[:on_open], do: on_open.()
        Keyword.get(opts, :default, {:error, :circuit_open})

      {:error, :not_found} ->
        Logger.warning("[CircuitBreaker] Fuse #{service} not installed, running unprotected")
        fun.()
    end
  end

  @doc """
  Run a function only if the circuit is closed.
  """
  def run_if_closed(service, fun, opts \\ []) do
    fuse_name = Map.get(@fuses, service, service)

    case :fuse.ask(fuse_name, :sync) do
      :ok -> fun.()
      :blown -> Keyword.get(opts, :default, {:error, :circuit_open})
      {:error, :not_found} -> fun.()
    end
  end

  @doc """
  Record a successful call.
  """
  def success(service) do
    fuse_name = Map.get(@fuses, service, service)
    :fuse.reset(fuse_name)
  end

  @doc """
  Record a failed call.
  """
  def failure(service) do
    fuse_name = Map.get(@fuses, service, service)
    :fuse.melt(fuse_name)
  end

  @doc """
  Check if a circuit is currently open.
  """
  def open?(service) do
    fuse_name = Map.get(@fuses, service, service)
    :fuse.ask(fuse_name, :sync) == :blown
  end

  @doc """
  Manually reset a circuit.
  """
  def reset(service) do
    fuse_name = Map.get(@fuses, service, service)
    :fuse.reset(fuse_name)
  end

  @doc """
  Get the current status of all circuits.
  """
  def status do
    Enum.map(@fuses, fn {name, fuse_name} ->
      state = case :fuse.ask(fuse_name, :sync) do
        :ok -> :closed
        :blown -> :open
        {:error, :not_found} -> :not_installed
      end
      {name, state}
    end)
    |> Map.new()
  end

  defp fuse_options(service) do
    config = Application.get_env(:message_service, :circuit_breaker, %{})
    service_config = Map.get(config, service, %{})

    max_failures = Map.get(service_config, :max_failures, 5)
    time_window = Map.get(service_config, :time_window, 10_000)
    reset_timeout = Map.get(service_config, :reset_timeout, 30_000)

    {{:standard, max_failures, time_window}, {:reset, reset_timeout}}
  end

  defp handle_error(_service, opts, error) do
    case Keyword.get(opts, :default) do
      nil -> {:error, {:circuit_breaker_error, error}}
      default -> default
    end
  end
end
