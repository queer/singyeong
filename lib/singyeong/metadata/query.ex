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
  @selector_names [
    "$min",
    "$max",
    "$avg",
  ]

  @opaque query_op_result() :: {:ok, boolean()} | {:error, binary()}
  @type key() :: binary()
  @type value() :: term()
  @type application_id() :: binary()
  @type client_id() :: binary()
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

  @type selector_name() ::
    :"$min"
    | :"$max"
    | :"$avg"

  ## OPS V2 ##

  @type path() :: String.t()

  @type op_v2() ::
    # {path, op, target}
    # | {op, ops}
    {:boolean, boolean_op_name(), path(), op_v2_target()}
    | {:logical, logical_op_name(), [op_v2()]}

  @type op_v2_target() ::
    # {:value, value}
    # | {:path, path, default}
    {:value, term()}
    | {:path, path(), term() | nil}

  typedstruct do
    field :application, String.t(), enforce: true
    field :restricted, boolean() | nil
    field :key, String.t() | nil
    field :droppable, boolean() | nil
    field :optional, boolean() | nil
    field :ops, [op_v2()] | [], enforce: true
    field :selector, {selector_name(), String.t()}
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
      ops: extract_v2_ops(json["ops"]),
      selector: extract_selector(json["selector"]),
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

  defp coerce_to_nil_binary(term), do: if is_binary(term), do: term, else: nil

  defp extract_selector(%{} = selector_map) do
    selector =
      selector_map
      |> Map.keys
      |> hd

    if selector in @selector_names do
      {String.to_atom(selector), selector_map[selector]}
    else
      nil
    end
  end
  defp extract_selector(_), do: nil

  defp extract_v2_ops(ops) do
    ops = ops || []
    Enum.map ops, &map_op/1
  end

  defp map_op(op_map) do
    case op_map do
      %{
        "path" => path,
        "op" => op,
        "to" => to,
      } when op in @boolean_op_names ->
        v2_op_to_boolean path, op, to

      %{
        "op" => op,
        "with" => ops,
      } when op in @logical_op_names ->
        v2_op_to_logical op, ops
    end
  end

  defp v2_op_to_boolean(path, op, %{"value" => value}) do
    {:boolean, atom_op(op), assert_path_invariants(path), {:value, value}}
  end

  defp v2_op_to_boolean(path, op, %{"path" => inner_path, "default" => default}) do
    {:boolean, atom_op(op), assert_path_invariants(path), {:path, assert_path_invariants(inner_path), default}}
  end

  defp v2_op_to_logical(op, ops) when is_list(ops) do
    {:logical, atom_op(op), Enum.map(ops, &map_op/1)}
  end

  defp atom_op("$" <> op) do
    "op_"
    |> Kernel.<>(op)
    |> String.to_atom
  end

  defp assert_path_invariants(path) do
    unless path != nil do
      raise ArgumentError, "path: must not be nil"
    end

    unless path != "" do
      raise ArgumentError, "path: must not be empty"
    end

    unless String.starts_with?(path, "/") do
      raise ArgumentError, "path: must start with `/`, got: '#{path}'"
    end

    path
  end
end
