defmodule MessageService.Schemas.Common do
  @moduledoc """
  Common schemas used across the Message Service API.
  """
  alias OpenApiSpex.Schema
  require OpenApiSpex

  defmodule SuccessResponse do
    @moduledoc "Generic success response"
    OpenApiSpex.schema(%{
      title: "SuccessResponse",
      description: "Generic success response",
      type: :object,
      properties: %{
        success: %Schema{type: :boolean, description: "Indicates if the operation was successful", example: true}
      },
      required: [:success],
      example: %{success: true}
    })
  end

  defmodule ErrorResponse do
    @moduledoc "Generic error response"
    OpenApiSpex.schema(%{
      title: "ErrorResponse",
      description: "Generic error response",
      type: :object,
      properties: %{
        success: %Schema{type: :boolean, description: "Indicates if the operation was successful", example: false},
        error: %Schema{type: :string, description: "Error message describing what went wrong"}
      },
      required: [:success, :error],
      example: %{
        success: false,
        error: "Invalid request parameters"
      }
    })
  end

  defmodule HealthResponse do
    @moduledoc "Health check response"
    OpenApiSpex.schema(%{
      title: "HealthResponse",
      description: "Health check response",
      type: :object,
      properties: %{
        status: %Schema{type: :string, description: "Health status", example: "healthy"},
        service: %Schema{type: :string, description: "Service name", example: "message-service"},
        version: %Schema{type: :string, description: "Service version", example: "1.0.0"}
      },
      required: [:status, :service, :version],
      example: %{
        status: "healthy",
        service: "message-service",
        version: "1.0.0"
      }
    })
  end

  defmodule ReadinessResponse do
    @moduledoc "Readiness check response"
    OpenApiSpex.schema(%{
      title: "ReadinessResponse",
      description: "Readiness check response with dependency status",
      type: :object,
      properties: %{
        ready: %Schema{type: :boolean, description: "Overall readiness status"},
        checks: %Schema{
          type: :object,
          description: "Individual dependency check results",
          properties: %{
            mongo: %Schema{type: :string, enum: ["ok", "error"], description: "MongoDB connection status"},
            redis: %Schema{type: :string, enum: ["ok", "error"], description: "Redis connection status"}
          }
        }
      },
      required: [:ready, :checks],
      example: %{
        ready: true,
        checks: %{
          mongo: "ok",
          redis: "ok"
        }
      }
    })
  end

  defmodule PaginationParams do
    @moduledoc "Common pagination parameters"
    OpenApiSpex.schema(%{
      title: "PaginationParams",
      description: "Common pagination parameters",
      type: :object,
      properties: %{
        limit: %Schema{type: :integer, description: "Maximum number of items to return", default: 50, minimum: 1, maximum: 100},
        before: %Schema{type: :string, description: "Cursor for fetching items before this ID"},
        after: %Schema{type: :string, description: "Cursor for fetching items after this ID"}
      }
    })
  end
end
