defmodule MessageService.HealthController do
  use Phoenix.Controller, formats: [:json]

  def index(conn, _params) do
    json(conn, %{status: "healthy", service: "message-service", version: "1.0.0"})
  end

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
