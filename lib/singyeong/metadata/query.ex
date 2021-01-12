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
  alias Singyeong.Store
  alias Singyeong.Store.Client
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

  @type boolean_op() :: {boolean_op_name(), value()}

  @type logical_op() :: {logical_op_name(), maybe_improper_list(boolean_op(), logical_op())}

  @type op() :: {String.t(), boolean_op() | logical_op()}

  typedstruct do
    field :application, binary(), enforce: true
    field :restricted, boolean() | nil
    field :key, binary() | nil
    field :droppable, boolean() | nil
    field :optional, boolean() | nil
    field :ops, ops(), enforce: true
  end

  typedstruct module: QueryError do
  end

  @spec json_to_query(map()) :: __MODULE__.t()
  def json_to_query(json) do
    %__MODULE__{
      application: json["application"],
      restricted: coerce_to_boolean(json["restricted"]),
      key: coerce_to_nil_binary(json["key"]),
      droppable: coerce_to_boolean(json["droppable"]),
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
    key = map |> Map.keys |> hd
    {op, value} = map |> Map.get(key) |> Enum.at(0)
    op_function = op |> String.to_atom |> operator_to_function
    if op in @logical_op_names and is_list(value) do
      {op_function, Enum.map(value, &recursive_atomify_op/1)}
    else
      {op_function, {key, value}}
    end
  end

  @doc """
  Given a query, execute it and return a list of client IDs.
  """
  @spec run_query(__MODULE__.t(), boolean()) :: {application_id(), [Client.t()] | []} | {nil, []}
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
    query.application
    |> is_binary
    |> if do
      query.application
    else
      raise "query.application: not string"
    end
  end

  defp process_query(query, app_id, broadcast) do
    allow_restricted = query.restricted
    ops =
      if allow_restricted do
        # If we allow restricted-mode clients, just run the query as-is
        query.ops
      else
        # Otherwise, explicitly require clients to not be restricted
        Utils.fast_list_concat query.ops, [{:op_eq, {"restricted", false}}]
      end

    {:ok, app_clients} = Store.get_app_clients app_id
    clients =
      app_clients
      |> MapSet.to_list
      |> Enum.map(&Store.get_client(app_id, &1))
      |> Enum.map(&elem(&1, 1))

    unless Enum.empty?(clients) do
      clients
      # Reduce the query over all clients. This actually runs the query...
      |> Enum.map(&{&1, reduce_query(&1, ops)})
      # ...then filter on clients that passed the query successfully...
      |> Enum.filter(&Enum.all?(elem(&1, 1)))
      # ...then map to the clients...
      |> Enum.map(&elem(&1, 0))
      # ...and finally convert it to a form the dispatcher understands
      |> convert_to_dispatch_form(app_id, clients, query, broadcast)
    else
      {:ok, []}
    end
  end

  defp convert_to_dispatch_form(res, app_id, clients, query, broadcast) do
    cond do
      Enum.empty?(res) and query.optional == true ->
        # If the query is optional, and the query returned no clients, just
        # return all clients and let the dispatcher figure it out
        {app_id, clients}

      not Enum.empty?(res) and query.key != nil and not broadcast ->
        # If the query is "consistently hashed", do the best we can to
        # ensure that it ends up on the same target client each time
        hash = :erlang.phash2 query.key
        # :erlang.phash2/1 will return a value on the range 0..2^27-1, so
        # we just modulus it and we're done
        idx = rem hash, length(res)
        # **ASSUMING THAT THE RESULTS OF THE QUERY HAVE NOT CHANGED**, the
        # target client will always be the same
        {app_id, [Enum.at(res, idx)]}

      true ->
        # Otherwise, just give back exactly what was asked for, even if it's nothing
        {app_id, res}
    end
  end

  @spec reduce_query(Client.t(), list()) :: [boolean()]
  defp reduce_query(%Client{} = client, ops) when is_list(ops) do
    if Enum.empty?(ops) do
      # If there's nothing to query, just return true
      [true]
    else
      # Otherwise, actually run it and see what comes out
      # ops = [{key, {$eq, "value"}}]
      do_reduce_query client, ops
    end
  end

  @spec do_reduce_query(Client.t(), list()) :: [boolean()]
  defp do_reduce_query(%Client{} = client, ops) when is_list(ops) do
    ops
    |> Enum.map(fn({op_function, {key, value}}) ->
      # do_run_query(metadata, key, %{$eq: "value"})
      do_run_query client.metadata, op_function, key, value
    end)
    |> Enum.map(fn(tuple) ->
      case tuple do
        {:ok, res} ->
          res

        {:error, _} ->
          # TODO: Send errors back to client
          false

        _ ->
          false
      end
    end)
  end

  @spec do_run_query(map(), atom(), binary(), term()) :: [query_op_result()]
  defp do_run_query(metadata, op_function, key, query_value) when is_map(metadata) do
    value = metadata[key]
    apply __MODULE__, op_function, [key, metadata, value, query_value]
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
