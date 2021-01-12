defmodule SingyeongWeb.GenericController do
  use SingyeongWeb, :controller
  alias Singyeong.Metadata.Query

  def not_found(conn, _params) do
    conn
    |> put_status(404)
    |> json(%{"code" => 404, "error" => "not found"})
  end

  def versions(conn, _params) do
    conn
    |> json(%{
      "singyeong" => Singyeong.version(),
      "api" => "v1",
    })
  end

  def query(conn, params) do
    {:ok, clients} =
      params
      |> Query.json_to_query
      |> Singyeong.Store.query
      |> Enum.map(&Map.from_struct)
      |> Enum.map(&Map.drop(&1, [:socket_pid]))

    conn
    |> json(clients)
  end

  def gateway_redirect(conn, _params) do
    conn
    |> redirect(to: "/gateway/websocket")
  end
end
