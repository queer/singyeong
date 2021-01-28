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
    clients =
      params
      |> Query.json_to_query
      |> Singyeong.Store.query
      |> Enum.map(&Map.from_struct/1)
      |> Enum.map(&Map.drop(&1, [:socket_pid]))
      |> Enum.map(fn client ->
        cleaned_metadata =
          client.metadata
          |> Enum.map(fn {k, v} ->
            case client.metadata_types[k] do
              :list ->
                out =
                  # Check notes in mnesia store for why this happens.
                  v
                  |> Enum.reject(fn
                    {"__singyeong:internal:metadata-store:index:" <> _i, _} -> true
                    _ -> false
                  end)
                  |> Enum.flat_map(fn {item, indices} ->
                    for i <- Map.keys(indices), do: {item, i}
                  end)
                  |> Enum.sort_by(&elem(&1, 1))
                  |> Enum.map(&elem(&1, 0))

                {k, out}

              _ ->
                {k, v}
            end
          end)
          |> Map.new

        %{client | metadata: cleaned_metadata}
      end)

    conn
    |> json(clients)
  end

  def gateway_redirect(conn, _params) do
    conn
    |> redirect(to: "/gateway/websocket")
  end
end
