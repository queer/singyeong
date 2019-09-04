defmodule Singyeong.Metadata.Query do
  @moduledoc """
  The "query engine" that makes metadata queries work. Currently, this is tied
  to specifics of how the Mnesia storage engine is implemented. This will need
  to be genericised somehow in a way that lets it become a property of the
  storage engine -- so to speak -- as it would make it much easier to implement
  a performant storage engine if the specifics of querying was able to take
  advantage of the specific backend being used.
  """

  alias Singyeong.MnesiaStore, as: Store
  alias Singyeong.Utils

  @opaque query_op_result() :: {:ok, boolean()} | {:error, binary()}

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
            # Pick the first application id that actually has all tags.
            hd matches
          end
      end
    case application do
      nil ->
        []
      _ ->
        allow_restricted = q["restricted"]
        ops =
          if allow_restricted do
            # If we allow restricted-mode clients, just run the query as-is
            q["ops"]
          else
            # Otherwise, explicitly require clients to not be restricted
            Utils.fast_list_concat q["ops"], [%{"restricted" => %{"$eq" => false}}]
          end
        {:ok, clients} = Store.get_clients application
        res =
          clients
          |> Enum.map(fn(x) -> {x, reduce_query(application, x, ops)} end)
          |> Enum.filter(fn({_, out}) -> Enum.all?(out) end)
          |> Enum.map(fn({client, _}) -> client end)
        cond do
          Enum.empty?(res) and q["optional"] == true ->
            # If the query is optional, and the query returned no nodes, just return
            # all nodes and let the dispatcher figure it out
            {application, clients}
          not Enum.empty?(res) and q["key"] != nil ->
            # If the query is "consistently hashed", do the best we can to
            # ensure that it ends up on the same target client each time
            hash = :erlang.phash2 q["key"]
            # :erlang.phash2/1 will return a value on the range 0..2^27-1, so
            # we just modulus it and we're done
            idx = rem hash, length(res)
            # **ASSUMING THAT THE RESULTS OF THE QUERY HAVE NOT CHANGED**, the
            # target client will always be the same
            {application, [Enum.at(res, idx)]}
          true ->
            # Otherwise, just give back exactly what was asked for, even if it's nothing
            {application, res}
        end
    end
  end

  @spec reduce_query(binary(), binary(), list()) :: [boolean()]
  defp reduce_query(app_id, client_id, q) when is_binary(client_id) and is_list(q) do
    if Enum.empty?(q) do
      # If there's nothing to query, just return true
      [true]
    else
      # Otherwise, actually run it and see what comes out
      # q = [%{key: %{$eq: "value"}}]
      {:ok, metadata} = Store.get_metadata app_id, client_id
      do_reduce_query metadata, q
    end
  end
  @spec do_reduce_query(map(), list()) :: [boolean()]
  defp do_reduce_query(metadata, q) when is_map(metadata) and is_list(q) do
    q
    |> Enum.map(fn(x) ->
      # x = %{key: %{$eq: "value"}}
      key = Map.keys(x) |> hd
      query = x[key]
      # do_run_query(metadata, key, %{$eq: "value"})
      do_run_query(metadata, key, query)
    end)
    |> Enum.map(fn(x) ->
      # x = [{:ok, true}, {:error, false}, ...]
      Enum.all?(x, fn(e) ->
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

  @spec do_run_query(map(), binary(), map()) :: [query_op_result()]
  defp do_run_query(metadata, key, q) when is_map(metadata) and is_map(q) do
    value = metadata[key]
    Map.keys(q)
    |> Enum.map(fn(op_atom) ->
      # > q = %{$eq: "value"}
      # which ultimately becomes
      # > op_eq metadata, key, value
      #
      # We convert each op into a function that can take the input and then map
      # the input into a result
      atom = operator_to_function op_atom
      args = [
        # The metadata key being queried against
        key,
        # The client's metadata
        metadata,
        # The value of the metadata
        value,
        # The incoming value to compare to the client's metadata,
        # ie op(value, q[op_atom])
        q[op_atom],
      ]
      apply Singyeong.Metadata.Query, atom, args
    end)
  end

  defp operator_to_function(op) when is_binary(op) do
    # $eq -> :op_eq
    op
    |> String.trim("$")
    |> as_op
    |> String.to_atom
  end
  defp as_op(s) when is_binary(s) do
    "op_" <> s
  end

  ## QUERY OPERATORS ##

  @spec op_eq(binary(), map(), any(), any()) :: query_op_result()
  def op_eq(_key, _client_metadata, metadata_value, value) do
    {:ok, metadata_value == value}
  end
  @spec op_ne(binary(), map(), any(), any()) :: query_op_result()
  def op_ne(_key, _client_metadata, metadata_value, value) do
    {:ok, metadata_value != value}
  end
  @spec op_gt(binary(), map(), any(), any()) :: query_op_result()
  def op_gt(_key, _client_metadata, metadata_value, value) do
    {:ok, metadata_value > value}
  end
  @spec op_gte(binary(), map(), any(), any()) :: query_op_result()
  def op_gte(_key, _client_metadata, metadata_value, value) do
    {:ok, metadata_value >= value}
  end
  @spec op_lt(binary(), map(), any(), any()) :: query_op_result()
  def op_lt(_key, _client_metadata, metadata_value, value) do
    {:ok, metadata_value < value}
  end
  @spec op_lte(binary(), map(), any(), any()) :: query_op_result()
  def op_lte(_key, _client_metadata, metadata_value, value) do
    {:ok, metadata_value <= value}
  end
  @spec op_in(binary(), map(), any(), list()) :: query_op_result()
  def op_in(_key, _client_metadata, metadata_value, value) do
    if is_list(value) do
      {:ok, metadata_value in value}
    else
      {:error, "value not a list"}
    end
  end
  @spec op_nin(binary(), map(), any(), list()) :: query_op_result()
  def op_nin(_key, _client_metadata, metadata_value, value) do
    if is_list(value) do
      {:ok, metadata_value not in value}
    else
      {:error, "value not a list"}
    end
  end
  @spec op_contains(binary(), map(), list(), any()) :: query_op_result()
  def op_contains(_key, _client_metadata, metadata_value, value) do
    if is_list(metadata_value) do
      {:ok, value in metadata_value}
    else
      {:error, "metadata not a list"}
    end
  end
  @spec op_ncontains(binary(), map(), list(), any()) :: query_op_result()
  def op_ncontains(_key, _client_metadata, metadata_value, value) do
    if is_list(metadata_value) do
      {:ok, value not in metadata_value}
    else
      {:error, "metadata not a list"}
    end
  end

  # Logical operators

  @spec op_and(binary(), map(), any(), any()) :: query_op_result()
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

  @spec op_or(binary(), map(), any(), any()) :: query_op_result()
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

  @spec op_nor(binary(), map(), any(), any()) :: query_op_result()
  def op_nor(key, client_metadata, metadata_value, value) do
    case op_or(key, client_metadata, metadata_value, value) do
      {:ok, res} ->
        {:ok, not res}
      {:error, err} ->
        {:error, err}
    end
  end
end
