defmodule MessageService.Endpoint do
  use Phoenix.Endpoint, otp_app: :message_service

  socket "/socket", MessageService.UserSocket, websocket: [timeout: 45_000], longpoll: false

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]
  plug Plug.Parsers, parsers: [:urlencoded, :multipart, :json], pass: ["*/*"], json_decoder: Jason
  plug Plug.MethodOverride
  plug Plug.Head
  plug CORSPlug, origin: ["*"]
  plug MessageService.Router
end
