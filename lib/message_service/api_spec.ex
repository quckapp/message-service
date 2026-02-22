defmodule MessageService.ApiSpec do
  @moduledoc """
  OpenAPI specification for the Message Service API.
  """
  alias OpenApiSpex.{Info, OpenApi, Paths, Server, Components, SecurityScheme}
  alias MessageService.{Endpoint, Router}
  @behaviour OpenApi

  @impl OpenApi
  def spec do
    %OpenApi{
      servers: [
        %Server{url: "http://localhost:4006", description: "Development Server"},
        %Server{url: "https://api.quickapp.com", description: "Production Server"}
      ],
      info: %Info{
        title: "Message Service API",
        description: "Message management and conversation API",
        version: "1.0.0"
      },
      paths: Paths.from_router(Router),
      components: %Components{
        securitySchemes: %{
          "bearer_auth" => %SecurityScheme{
            type: "http",
            scheme: "bearer",
            bearerFormat: "JWT",
            description: "JWT Bearer token authentication"
          },
          "api_key" => %SecurityScheme{
            type: "apiKey",
            name: "X-API-Key",
            in: "header",
            description: "API Key authentication"
          }
        }
      }
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
