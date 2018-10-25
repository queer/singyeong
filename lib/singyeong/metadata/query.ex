defmodule Singyeong.Metadata.Query do
  alias Singyeong.Metadata.Store

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
    |> Enum.map(fn(x) -> {x, reduce_query(x, ops)} end)
    |> Enum.filter(fn({_, out}) -> Enum.all?(out) end)
    |> Enum.map(fn({client, _}) -> client end)
  end

  defp reduce_query(client_id, q) when is_binary(client_id) and is_list(q) do
    if length(q) == 0 do
      [true]
    else
      metadata = Store.get_metadata client_id
      do_reduce_query metadata, q
    end
  end
  defp do_reduce_query(metadata, q) when is_map(metadata) and is_list(q) do
    out =
      q
      |> Enum.map(fn(x) ->
        # x = {key: {$eq: "value"}}
        key = Map.keys(x) |> hd
        query = x[key]
        do_run_query(metadata, key, query)
      end)
      |> Enum.map(fn(x) ->
        # x = [{:ok, true}, {:error, false}, ...]
        x |> Enum.all?(fn(e) ->
            case e do
              {:ok, res} ->
                res
              {:error, _} ->
                # TODO: Figure out how to warn the initiating client about errors
                false
              _ ->
                false
            end
          end)
      end)
    out
  end

  defp do_run_query(metadata, key, q) when is_map(metadata) and is_map(q) do
    Map.keys(q)
    |> Enum.map(fn(x) ->
      atom = operator_to_function(x)
      f = fn(z) -> apply(Singyeong.Metadata.Query, atom, z) end
      {x, f}
    end)
    |> Enum.map(fn({x, f}) ->
      field = metadata[key]
      value = field["value"]
      f.([key, metadata, value, q[x]])
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

  def op_eq(_key, _client_metadata, metadata_value, value) do
    {:ok, metadata_value == value}
  end
  def op_ne(_key, _client_metadata, metadata_value, value) do
    {:ok, metadata_value != value}
  end
  def op_gt(_key, _client_metadata, metadata_value, value) do
    {:ok, metadata_value > value}
  end
  def op_gte(_key, _client_metadata, metadata_value, value) do
    {:ok, metadata_value >= value}
  end
  def op_lt(_key, _client_metadata, metadata_value, value) do
    {:ok, metadata_value < value}
  end
  def op_lte(_key, _client_metadata, metadata_value, value) do
    {:ok, metadata_value <= value}
  end
  def op_in(_key, _client_metadata, metadata_value, value) do
    if is_list(value) do
      {:ok, metadata_value in value}
    else
      {:error, "value not a list"}
    end
  end
  def op_nin(_key, _client_metadata, metadata_value, value) do
    if is_list(value) do
      {:ok, metadata_value not in value}
    else
      {:error, "value not a list"}
    end
  end
  def op_contains(_key, _client_metadata, metadata_value, value) do
    if is_list(metadata_value) do
      {:ok, value in metadata_value}
    else
      {:error, "metadata not a list"}
    end
  end
  def op_ncontains(_key, _client_metadata, metadata_value, value) do
    if is_list(metadata_value) do
      {:ok, value not in metadata_value}
    else
      {:error, "metadata not a list"}
    end
  end

  # Logical operators

  def op_and(key, client_metadata, _metadata_value, value) do
    if is_list(value) do
      res =
        value
        |> Enum.map(fn(x) -> do_reduce_query(client_metadata, [%{key => x}]) end)
        # We get back a list from the previous step, so we need to extract the
        # first element of the list in order for this to be accurate
        |> Enum.map(fn([x]) -> x end)
        |> Enum.all?
      {:ok, res}
    else
      {:error, "$and query not a map"}
    end
  end

  def op_or(key, client_metadata, _metadata_value, value) do
    if is_list(value) do
      res =
        value
        |> Enum.map(fn(x) -> do_reduce_query(client_metadata, [%{key => x}]) end)
        # We get back a list from the previous step, so we need to extract the
        # first element of the list in order for this to be accurate
        |> Enum.map(fn([x]) -> x end)
        |> Enum.any?
      {:ok, res}
    else
      {:error, "$or query not a map"}
    end
  end

  def op_nor(key, client_metadata, metadata_value, value) do
    case op_or(key, client_metadata, metadata_value, value) do
      {:ok, res} ->
        {:ok, not res}
      {:error, err} ->
        {:error, err}
      _ ->
        {:error, "$or unknown error"}
    end
  end

  # The problem with $not is that it would return a LIST of values, but all the
  # other operators would return a SINGLE VALUE.
  # TODO: Come up with a better solution...
  def op_not(_key, _client_metadata, _metadata, _value) do
    {:error, "$not isn't implemented"}
  end
end
