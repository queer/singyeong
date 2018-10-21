defmodule Singyeong.Metadata.Query do
  alias Singyeong.Metadata.Store
  # - `$and`
  # - `$or`
  # - `$nor`
  # - `$not`


  @doc """
  Given a query, execute it and return a list of client IDs.
  """
  def run_query(q) when is_map(q) do
    application = q["application"]
    ops = q["ops"]
    {:ok, clients} = Store.get_all_clients application
    for client <- clients do
      # Super lazy deletion filter
      metadata = Store.get_metadata client
      unless is_nil(metadata) or metadata == %{} do
        if Map.has_key?(metadata, "last_heartbeat_time") do
          last =
            if is_map(metadata["last_heartbeat_time"]) do
              metadata["last_heartbeat_time"]["value"]
            else
              nil
            end
          unless is_nil(last) do
            now = :os.system_time :millisecond
            if (last + (Singyeong.Gateway.heartbeat_interval * 1.5)) < now do
              Store.remove_client application, client
            end
          end
        end
      else
        Store.remove_client application, client
      end
    end
    {:ok, clients} = Store.get_all_clients application
    clients
    |> Enum.map(fn(x) -> reduce_query(x, ops) end)
    |> Enum.filter(fn({_, out}) -> Enum.all?(out) end)
    |> Enum.map(fn({client, _}) -> client end)
  end

  defp reduce_query(client_id, q) when is_map(q) do
    metadata = Store.get_metadata client_id
    out =
      q
      |> Map.keys
      |> Enum.map(fn(x) ->
        data = q[x]
        run_query(metadata, x, data)
      end)
      |> Enum.map(fn(x) ->
        # x = [{:ok, true}, {:error, false}, ...]
        x |> Enum.all?(fn(e) ->
            case e do
              {:ok, res} ->
                res
              {:error, _} ->
                false
              _ ->
                false
            end
          end)
      end)
    {client_id, out}
  end

  defp run_query(metadata, key, q) when is_map(metadata) and is_map(q) do
    Map.keys(q)
    |> Enum.map(fn(x) ->
      atom = operator_to_function(x)
      f = fn(z) -> apply(Singyeong.Metadata.Query, atom, z) end
      {x, f}
    end)
    |> Enum.map(fn({x, f}) ->
      field = metadata[key]
      value = field["value"]
      f.([value, q[x]])
    end)
  end

  defp operator_to_function(op) when is_binary(op) do
    op
    |> String.trim("$")
    |> as_op
    |> String.to_atom
  end
  defp as_op(s) when is_binary(s) do
    "op_" <> s
  end

  ## QUERY OPERATORS ##

  def op_eq(metadata, value) do
    {:ok, metadata == value}
  end
  def op_ne(metadata, value) do
    {:ok, metadata != value}
  end
  def op_gt(metadata, value) do
    {:ok, metadata > value}
  end
  def op_gte(metadata, value) do
    {:ok, metadata>= value}
  end
  def op_lt(metadata, value) do
    {:ok, metadata < value}
  end
  def op_lte(metadata, value) do
    {:ok, metadata<= value}
  end
  def op_in(metadata, value) do
    if is_list(value) do
      {:ok, metadata in value}
    else
      {:error, "value not a list"}
    end
  end
  def op_nin(metadata, value) do
    if is_list(value) do
      {:ok, metadata not in value}
    else
      {:error, "value not a list"}
    end
  end

  # TODO: Logical operators
end
