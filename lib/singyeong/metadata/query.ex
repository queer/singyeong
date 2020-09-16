defmodule Singyeong.Metadata.Query do
  @moduledoc """
  The "query engine" that makes metadata queries work. Currently, this is tied
  to specifics of how the Mnesia storage engine is implemented. This will need
  to be genericised somehow in a way that lets it become a property of the
  storage engine -- so to speak -- as it would make it much easier to implement
  a performant storage engine if the specifics of querying was able to take
  advantage of the specific backend being used.
  """

  use TypedStruct
  alias Singyeong.MnesiaStore, as: Store
  alias Singyeong.Utils

  @boolean_op_names [
    "$eq",
    "$ne",
    "$gt",
    "$gte",
    "$lt",
    "$lte",
    "$in",
    "$nin",
    "$contains",
    "$ncontains",
  ]
  @logical_op_names [
    "$and",
    "$or",
    "$nor",
  ]

  @opaque query_op_result() :: {:ok, boolean()} | {:error, binary()}
  @type key() :: binary()
  @type value() :: term()
  @type application_id() :: binary()
  @type client_id() :: binary()
  @type ops() :: [op()] | []
  @type boolean_op_name() ::
    :"$eq"
    | :"$ne"
    | :"$gt"
    | :"$gte"
    | :"$lt"
    | :"$lte"
    | :"$in"
    | :"$nin"
    | :"$contains"
    | :"$ncontains"

  @type logical_op_name() ::
    :"$and"
    | :"$or"
    | :"$nor"

  @type boolean_op() :: %{
      required(boolean_op_name()) => value()
    }

  @type logical_op() :: %{
    required(logical_op_name()) => maybe_improper_list(boolean_op(), logical_op())
  }

  @type op() :: %{
    required(binary()) => boolean_op() | logical_op()
  }

  typedstruct do
    field :application, binary(), enforce: true
    field :restricted, boolean() | nil
    field :key, binary() | nil
    field :droppable, boolean() | nil
    field :optional, boolean() | nil
    field :ops, ops(), enforce: true
  end

  @spec json_to_query(map()) :: __MODULE__.t()
  def json_to_query(json) do
    %__MODULE__{
      application: json["application"],
      restricted: coerce_to_boolean(json["restricted"]),
      key: coerce_to_nil_binary(json["key"]),
      droppable: coerce_to_nil_binary(json["droppable"]),
      optional: coerce_to_boolean(json["optional"]),
      ops: extract_ops(json["ops"])
    }
  end

  defp coerce_to_boolean(term) do
    case term do
      true -> true
      false -> false
      "true" -> true
      "false" -> false
      _ -> false
    end
  end

  defp coerce_to_nil_binary(term) do
    if is_binary(term), do: term, else: nil
  end

  defp extract_ops(ops) do
    # Something something don't trust users X:
    (ops || [])
    |> Enum.filter(fn map ->
      if is_map(map) do
        key =
          map
          |> Map.keys
          |> hd

        op = Map.get map, key
        recursive_check_op op
      else
        false
      end
    end)
    |> Enum.map(&recursive_atomify_op/1)
  end

  defp recursive_check_op(map) when is_map(map) do
    op = map |> Map.keys |> hd
    value = Map.get map, op
    if op in @logical_op_names and is_list(value) do
      value |> Enum.all?(&recursive_check_op/1)
    else
      op in @boolean_op_names
    end
  end

  defp recursive_atomify_op(map) when is_map(map) do
    op = map |> Map.keys |> hd
    value = Map.get map, op
    if op in @logical_op_names and is_list(value) do
      %{String.to_atom(op) => Enum.map(value, &recursive_atomify_op/1)}
    else
      %{String.to_atom(op) => value}
    end
  end

  @doc """
  Given a query, execute it and return a list of client IDs.
  """
  @spec run_query(__MODULE__.t(), boolean()) :: {application_id(), [client_id()] | []} | {nil, []}
  def run_query(%__MODULE__{} = query, broadcast) do
    application = query_app_target query
    case application do
      nil ->
        {nil, []}

      _ ->
        process_query query, application, broadcast
    end
  end

  defp query_app_target(%__MODULE__{} = query) do
    cond do
      is_binary query.application ->
        # Normal case, just return the application name
        query.application

      is_list query.application ->
        # If we're passed a list, try to discover the application id
        {:ok, matches} = Singyeong.Discovery.discover_service query.application
        if matches == [] do
          nil
        else
          # Pick the first application id that actually has all tags.
          hd matches
        end

      true ->
        raise "query.application is neither binary nor list, which is invalid!"
    end
  end

  defp process_query(query, application, broadcast) do
    allow_restricted = query.restricted
    ops =
      if allow_restricted do
        # If we allow restricted-mode clients, just run the query as-is
        query.ops
      else
        # Otherwise, explicitly require clients to not be restricted
        Utils.fast_list_concat query.ops, [%{"restricted" => %{:"$eq" => false}}]
      end
    {:ok, clients} = Store.get_clients application
    res =
      clients
      |> Enum.map(fn(client) -> {client, reduce_query(application, client, ops)} end)
      |> Enum.filter(fn({_, out}) -> Enum.all?(out) end)
      |> Enum.map(fn({client, _}) -> client end)

    cond do
      Enum.empty?(res) and query.optional == true ->
        # If the query is optional, and the query returned no nodes, just return
        # all nodes and let the dispatcher figure it out
        {application, clients}

      not Enum.empty?(res) and query.key != nil ->
        {:ok, clients} = Store.get_clients application
        clients
        |> Enum.map(fn(x) -> {x, reduce_query(application, x, ops)} end)
        |> Enum.filter(fn({_, out}) -> Enum.all?(out) end)
        |> Enum.map(fn({client, _}) -> client end)
        |> convert_to_dispatch_form(application, clients, query, broadcast)

      true ->
        # Otherwise, just give back whatever we've got, even if it was empty
        {application, clients}
    end
  end

  defp convert_to_dispatch_form(res, application, clients, query, broadcast) do
    cond do
      Enum.empty?(res) and query.optional == true ->
        # If the query is optional, and the query returned no nodes, just return
        # all nodes and let the dispatcher figure it out
        {application, clients}

      not Enum.empty?(res) and query.key != nil and not broadcast ->
        # If the query is "consistently hashed", do the best we can to
        # ensure that it ends up on the same target client each time
        hash = :erlang.phash2 query.key
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

  @spec reduce_query(binary(), binary(), list()) :: [boolean()]
  defp reduce_query(app_id, client_id, ops) when is_binary(client_id) and is_list(ops) do
    if Enum.empty?(ops) do
      # If there's nothing to query, just return true
      [true]
    else
      # Otherwise, actually run it and see what comes out
      # ops = [%{key: %{$eq: "value"}}]
      {:ok, metadata} = Store.get_metadata app_id, client_id
      do_reduce_query metadata, ops
    end
  end

  @spec do_reduce_query(map(), list()) :: [boolean()]
  defp do_reduce_query(metadata, ops) when is_map(metadata) and is_list(ops) do
    ops
    |> Enum.map(fn(x) ->
      # x = %{key: %{$eq: "value"}}
      key = Map.keys(x) |> hd
      query = x[key]
      # do_run_query(metadata, key, %{$eq: "value"})
      do_run_query metadata, key, query
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
  defp do_run_query(metadata, key, query) when is_map(metadata) and is_map(query) do
    value = metadata[key]
    query
    |> Map.keys
    |> Enum.map(fn(op_atom) ->
      # > query = %{$eq: "value"}
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
        # ie op(value, query[op_atom])
        query[op_atom],
      ]
      apply __MODULE__, atom, args
    end)
  end

  defp operator_to_function(op) when is_atom(op), do: op |> Atom.to_string |> operator_to_function
  defp operator_to_function("$" <> op) do
    # $eq -> :op_eq
    op
    |> as_op
    |> String.to_atom
  end

  defp as_op(s) when is_binary(s) do
    "op_#{s}"
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
