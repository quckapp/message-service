defmodule MessageService.SwaggerController do
  @moduledoc """
  Controller for serving Swagger UI and OpenAPI specification.
  """
  use Phoenix.Controller, formats: [:json, :html]

  alias OpenApiSpex.OpenApi
  alias MessageService.ApiSpec

  @doc """
  Serves the OpenAPI specification as JSON.
  """
  def openapi_spec(conn, _params) do
    spec = ApiSpec.spec()
    json(conn, spec)
  end

  @doc """
  Serves the Swagger UI HTML page.
  """
  def swagger_ui(conn, _params) do
    html(conn, swagger_ui_html())
  end

  defp swagger_ui_html do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Message Service API - Swagger UI</title>
      <link rel="stylesheet" type="text/css" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css">
      <style>
        html {
          box-sizing: border-box;
          overflow-y: scroll;
        }
        *,
        *:before,
        *:after {
          box-sizing: inherit;
        }
        body {
          margin: 0;
          background: #fafafa;
        }
        .swagger-ui .topbar {
          background-color: #1a1a2e;
        }
        .swagger-ui .topbar .download-url-wrapper .select-label {
          color: #fff;
        }
        .swagger-ui .info .title {
          color: #1a1a2e;
        }
        .swagger-ui .scheme-container {
          background: #fff;
          box-shadow: 0 1px 2px 0 rgba(0,0,0,.15);
        }
      </style>
    </head>
    <body>
      <div id="swagger-ui"></div>
      <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js" charset="UTF-8"></script>
      <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-standalone-preset.js" charset="UTF-8"></script>
      <script>
        window.onload = function() {
          const ui = SwaggerUIBundle({
            url: "/swagger/openapi.json",
            dom_id: '#swagger-ui',
            deepLinking: true,
            presets: [
              SwaggerUIBundle.presets.apis,
              SwaggerUIStandalonePreset
            ],
            plugins: [
              SwaggerUIBundle.plugins.DownloadUrl
            ],
            layout: "StandaloneLayout",
            persistAuthorization: true,
            displayRequestDuration: true,
            filter: true,
            showExtensions: true,
            showCommonExtensions: true,
            syntaxHighlight: {
              activate: true,
              theme: "monokai"
            }
          });
          window.ui = ui;
        };
      </script>
    </body>
    </html>
    """
  end
end
