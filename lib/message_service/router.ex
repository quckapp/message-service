defmodule MessageService.Router do
  use Phoenix.Router
  import Phoenix.Controller

  pipeline :api do
    plug :accepts, ["json"]
    plug MessageService.Plugs.AuthPlug
  end

  pipeline :public do
    plug :accepts, ["json"]
  end

  scope "/api/v1/messages", MessageService do
    pipe_through :api

    post "/", MessageController, :send
    get "/conversation/:conversation_id", MessageController, :index
    get "/:message_id", MessageController, :show
    put "/:message_id", MessageController, :edit
    delete "/:message_id", MessageController, :delete
    post "/:message_id/reactions", MessageController, :add_reaction
    delete "/:message_id/reactions/:emoji", MessageController, :remove_reaction
    post "/conversation/:conversation_id/read", MessageController, :mark_read
    post "/conversation/:conversation_id/delivered", MessageController, :mark_delivered
    get "/conversation/:conversation_id/search", MessageController, :search
  end

  scope "/health", MessageService do
    pipe_through :public
    get "/", HealthController, :index
    get "/ready", HealthController, :ready
  end
end
