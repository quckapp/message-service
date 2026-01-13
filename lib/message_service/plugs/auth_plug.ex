defmodule MessageService.Plugs.AuthPlug do
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        case MessageService.Guardian.decode_and_verify(token) do
          {:ok, claims} -> assign(conn, :current_user_id, claims["sub"])
          {:error, _} -> conn |> put_status(401) |> json(%{error: "Invalid token"}) |> halt()
        end
      _ -> conn |> put_status(401) |> json(%{error: "Missing authorization"}) |> halt()
    end
  end
end
