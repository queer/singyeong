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
                # Check notes in mnesia store for why this happens.
                {k, flatten_list(v)}

              :map ->
                {k, process_map(v)}

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

  defp flatten_list(list) do
    list
    |> Enum.reject(fn
      {"__singyeong:internal:metadata-store:index:" <> _i, _} -> true
      _ -> false
    end)
    |> Enum.flat_map(fn {item, indices} ->
      for i <- Map.keys(indices), do: {item, i}
    end)
    |> Enum.sort_by(&elem(&1, 1))
    |> Enum.map(&elem(&1, 0))
    |> Enum.map(fn x ->
      cond do
        is_map(x) and is_actually_list?(x) ->
          flatten_list x

        is_map(x) ->
          process_map x

        true ->
          x
      end
    end)
  end

  defp process_map(map) do
    map
    |> Enum.map(fn {k, v} ->
      cond do
        is_map(v) and is_actually_list?(v) -> {k, flatten_list(v)}
        is_map(v) -> {k, process_map(v)}
        true -> {k, v}
      end
    end)
    |> Map.new
  end

  defp is_actually_list?(map) do
    map
    |> Map.keys
    |> Enum.any?(fn x ->
      is_binary(x) and String.starts_with?(x, "__singyeong:internal:metadata-store:index:")
    end)
  end

  def gateway_redirect(conn, _params) do
    conn
    |> redirect(to: "/gateway/websocket")
  end
end
