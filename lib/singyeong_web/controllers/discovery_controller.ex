defmodule SingyeongWeb.DiscoveryController do
  use SingyeongWeb, :controller
  alias Singyeong.Cluster

  @doc """
  For some input array ["tag", "tag", ...], usage is
  `GET /whatever/discovery/tags?q=[%22tag%22,%20%22tag%22,%20...]
  """
  def by_tags(conn, _params) do
    # Allow using query params without parsing them ourselves
    conn = conn |> fetch_query_params
    # conn.query_params is a %{k => v} of the querystring params
    # Can't have duplicate query params it seems; eg. no
    # "/whatever?a=b&a=c&b=d"
    # Because of this, we instead will just pass a urlencoded JSON array of
    # tags that we want to query on
    if Map.has_key?(conn.query_params, "q") do
      query =
        conn.query_params["q"]
        |> URI.decode
        |> Jason.decode!
      results = Cluster.discover query
      results =
        results
        |> Map.values()
        |> Enum.filter(fn x -> not is_nil(x) end)
        |> Enum.filter(fn x -> {:ok, _} = x end)
        |> Enum.map(fn {:ok, x} -> x end)
        |> Enum.concat
      conn
      |> json(%{"status" => "ok", "result" => results})
    else
      conn
      |> put_status(400)
      |> json(%{"status" => "error", "error" => "no query parameter"})
    end
  end
end
