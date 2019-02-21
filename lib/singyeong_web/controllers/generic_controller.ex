defmodule SingyeongWeb.GenericController do
  use SingyeongWeb, :controller

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
end
