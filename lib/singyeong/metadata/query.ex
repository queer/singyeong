defmodule Singyeong.Metadata.Query do
  alias Singyeong.MnesiaStore, as: Store

  @doc """
  Given a query, execute it and return a list of client IDs.
  """
  def run_query(q) when is_map(q) do
    application =
      cond do
        is_binary q["application"] ->
          # Normal case, just return the application name
          q["application"]
        is_list q["application"] ->
          # If we're passed a list, try to discover the application id
          {:ok, matches} = Singyeong.Discovery.discover_service q["application"]
          if matches == [] do
            nil
          else
            hd matches
          end
      end
    case application do
      nil ->
        []
      _ ->
        allow_restricted = q["restricted"]
        ops =
          cond do
            allow_restricted ->
              # If we allow restricted-mode clients, just run the query as-is
              q["ops"]
            true ->
              # Otherwise, explicitly require clients to not be restricted
              [%{"restricted" => %{"$eq" => false}} | q["ops"]]
          end
        {:ok, clients} = Store.get_clients application
        # Kind-of silly filter to get rid of clients that haven't heartbeated
        # lately and are still in the metadata store for some reason
        for client <- clients do
          {:ok, last} = Store.get_metadata application, client, "last_heartbeat_time"
          now = :os.system_time :millisecond
          if (last + (Singyeong.Gateway.heartbeat_interval * 1.5)) < now do
            Store.delete_client application, client
          end
        end
        {:ok, clients} = Store.get_clients application
        res =
          clients
          |> Enum.map(fn(x) -> {x, reduce_query(application, x, ops)} end)
          |> Enum.filter(fn({_, out}) -> Enum.all?(out) end)
          |> Enum.map(fn({client, _}) -> client end)
        if length(res) == 0 and q["optional"] == true do
          # If the query is optional, and the query returned no nodes, just return
          # all nodes and let the dispatcher figure it out
          clients
        else
          res
        end
    end
  end

  defp reduce_query(app_id, client_id, q) when is_binary(client_id) and is_list(q) do
    if length(q) == 0 do
      [true]
    else
      {:ok, metadata} = Store.get_metadata app_id, client_id
      do_reduce_query metadata, q
    end
  end
  defp do_reduce_query(metadata, q) when is_map(metadata) and is_list(q) do
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
  end

  defp do_run_query(metadata, key, q) when is_map(metadata) and is_map(q) do
    Map.keys(q)
    |> Enum.map(fn(x) ->
      atom = operator_to_function(x)
      f = fn(z) -> apply(Singyeong.Metadata.Query, atom, z) end
      {x, f}
    end)
    |> Enum.map(fn({x, f}) ->
      value = metadata[key]
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

  @spec op_eq(binary(), map(), any(), any()) :: {:ok, boolean()} | {:error, binary()}
  def op_eq(_key, _client_metadata, metadata_value, value) do
    {:ok, metadata_value == value}
  end
  @spec op_ne(binary(), map(), any(), any()) :: {:ok, boolean()} | {:error, binary()}
  def op_ne(_key, _client_metadata, metadata_value, value) do
    {:ok, metadata_value != value}
  end
  @spec op_gt(binary(), map(), any(), any()) :: {:ok, boolean()} | {:error, binary()}
  def op_gt(_key, _client_metadata, metadata_value, value) do
    {:ok, metadata_value > value}
  end
  @spec op_gte(binary(), map(), any(), any()) :: {:ok, boolean()} | {:error, binary()}
  def op_gte(_key, _client_metadata, metadata_value, value) do
    {:ok, metadata_value >= value}
  end
  @spec op_lt(binary(), map(), any(), any()) :: {:ok, boolean()} | {:error, binary()}
  def op_lt(_key, _client_metadata, metadata_value, value) do
    {:ok, metadata_value < value}
  end
  @spec op_lte(binary(), map(), any(), any()) :: {:ok, boolean()} | {:error, binary()}
  def op_lte(_key, _client_metadata, metadata_value, value) do
    {:ok, metadata_value <= value}
  end
  @spec op_in(binary(), map(), any(), list()) :: {:ok, boolean()} | {:error, binary()}
  def op_in(_key, _client_metadata, metadata_value, value) do
    if is_list(value) do
      {:ok, metadata_value in value}
    else
      {:error, "value not a list"}
    end
  end
  @spec op_nin(binary(), map(), any(), list()) :: {:ok, boolean()} | {:error, binary()}
  def op_nin(_key, _client_metadata, metadata_value, value) do
    if is_list(value) do
      {:ok, metadata_value not in value}
    else
      {:error, "value not a list"}
    end
  end
  @spec op_contains(binary(), map(), list(), any()) :: {:ok, boolean()} | {:error, binary()}
  def op_contains(_key, _client_metadata, metadata_value, value) do
    if is_list(metadata_value) do
      {:ok, value in metadata_value}
    else
      {:error, "metadata not a list"}
    end
  end
  @spec op_ncontains(binary(), map(), list(), any()) :: {:ok, boolean()} | {:error, binary()}
  def op_ncontains(_key, _client_metadata, metadata_value, value) do
    if is_list(metadata_value) do
      {:ok, value not in metadata_value}
    else
      {:error, "metadata not a list"}
    end
  end

  # Logical operators

  @spec op_and(binary(), map(), any(), any()) :: {:ok, boolean()} | {:error, binary()}
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

  @spec op_or(binary(), map(), any(), any()) :: {:ok, boolean()} | {:error, binary()}
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

  @spec op_nor(binary(), map(), any(), any()) :: {:ok, boolean()} | {:error, binary()}
  def op_nor(key, client_metadata, metadata_value, value) do
    case op_or(key, client_metadata, metadata_value, value) do
      {:ok, res} ->
        {:ok, not res}
      {:error, err} ->
        {:error, err}
    end
  end

  # The problem with $not is that it would return a LIST of values, but all the
  # other operators would return a SINGLE VALUE.
  # TODO: Come up with a better solution...
  @spec op_not(binary(), map(), any(), any()) :: {:ok, boolean()} | {:error, binary()}
  def op_not(_key, _client_metadata, _metadata, _value) do
    {:error, "$not isn't implemented"}
  end
end
