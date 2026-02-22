defmodule MessageService.HealthController do
  use Phoenix.Controller, formats: [:json]
  use OpenApiSpex.ControllerSpecs

  alias MessageService.Schemas.Common

  tags ["Health"]

  operation :index,
    summary: "Health check",
    description: "Basic health check endpoint to verify the service is running",
    responses: [
      ok: {"Service is healthy", "application/json", Common.HealthResponse}
    ]

  def index(conn, _params) do
    json(conn, %{status: "healthy", service: "message-service", version: "1.0.0"})
  end

  operation :ready,
    summary: "Readiness check",
    description: "Readiness check endpoint to verify all service dependencies are available",
    responses: [
      ok: {"Service is ready", "application/json", Common.ReadinessResponse},
      service_unavailable: {"Service is not ready", "application/json", Common.ReadinessResponse}
    ]

  def ready(conn, _params) do
    checks = %{mongo: check_mongo(), redis: check_redis()}
    all_healthy = Enum.all?(checks, fn {_, status} -> status == :ok end)
    status_code = if all_healthy, do: 200, else: 503
    conn |> put_status(status_code) |> json(%{ready: all_healthy, checks: checks})
  end

  defp check_mongo do
    case Mongo.command(:message_mongo, %{ping: 1}) do
      {:ok, _} -> :ok
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp check_redis do
    case Redix.command(:message_redis, ["PING"]) do
      {:ok, "PONG"} -> :ok
      _ -> :error
    end
  rescue
    _ -> :error
  end
end
