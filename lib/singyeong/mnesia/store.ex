defmodule Singyeong.Mnesia.Store do
  @moduledoc """
  The default Mnesia-backed metadata etc. store.
  """

  alias Singyeong.Metadata
  alias Singyeong.Metadata.{Query, Types}
  alias Singyeong.Store.Client
  require Lethe

  @behaviour Singyeong.Store

  @clients :clients
  @apps :apps

  @impl Singyeong.Store
  def start do
    # If we don't stop Mnesia first, then creating the schema will spuriously
    # fail, but then creating the schema will fail in funny ways, meaning that
    # Mnesia can never start properly. This ensures in a store-agnostic way
    # that Mnesia can do the right thing.
    :stopped = :mnesia.stop()
    :mnesia.create_schema []
    :ok = :mnesia.start()

    # General storage
    create_table_with_indexes @clients,   [attributes: [:composite_id, :client]], [:client]
    create_table_with_indexes @apps,      [attributes: [:app_id, :app]], [:app_id]

    :ok
  end

  defp create_table_with_indexes(table, opts, index_keys) do
    :mnesia.create_table table, opts
    for index <- index_keys, do: :mnesia.add_table_index table, index
  end

  @impl Singyeong.Store
  def stop do
    :mnesia.delete_table @apps
    :mnesia.delete_table @clients
    :mnesia.stop()
    :mnesia.delete_schema []
    :ok
  end

  @impl Singyeong.Store
  def add_client(%Client{app_id: app_id, client_id: client_id} = client) do
    if client_exists?(app_id, client_id) do
      raise "#{client_id}: can't add to #{app_id}: already exists"
    end
    :mnesia.transaction(fn -> do_add_client(client) end)
    |> return_result_or_error
  end

  defp do_add_client(%Client{app_id: app_id, client_id: client_id} = client) do
    :ok = :mnesia.write {@clients, {app_id, client_id}, client}
    {:ok, mapset} = get_app_clients app_id
    mapset = MapSet.put mapset, client_id
    :ok = :mnesia.write {@apps, app_id, mapset}
  end

  @impl Singyeong.Store
  def update_client(%Client{} = client) do
    :mnesia.transaction(fn -> do_update_client(client) end)
    |> return_result_or_error
  end

  defp do_update_client(%Client{app_id: app_id, client_id: client_id} = client) do
    {:ok, mapset} = get_app_clients app_id
    unless MapSet.member?(mapset, client_id) do
      raise "Couldn't update client #{client_id} in app #{app_id}: it doesn't already exist"
    end
    :ok = :mnesia.write {@clients, {app_id, client_id}, client}
    mapset = MapSet.put mapset, client_id
    :ok = :mnesia.write {@apps, app_id, mapset}
    client
  end

  @impl Singyeong.Store
  def get_client(app_id, client_id) do
    :mnesia.transaction(fn -> do_get_client({app_id, client_id}) end)
    |> return_read_result_or_error(@clients, {app_id, client_id})
  end

  defp do_get_client({app_id, client_id} = composite_id) do
    case :mnesia.read({@clients, composite_id}) do
      [{@clients, ^composite_id, client}] ->
        {:ok, app_clients} = get_app_clients client.app_id
        unless MapSet.member?(app_clients, client_id) do
          raise "Couldn't get client #{client_id}: not a member of app #{app_id}"
        end
        client

      [] ->
        nil
    end
  end

  @impl Singyeong.Store
  def remove_client(%Client{app_id: app_id, client_id: client_id}) do
    remove_client app_id, client_id
  end

  def remove_client(app_id, client_id) do
    {:ok, mapset} = get_app_clients app_id
    :mnesia.transaction fn ->
      mapset = MapSet.delete mapset, client_id
      :ok = :mnesia.write({@apps, app_id, mapset})
    end
    :mnesia.transaction(fn -> do_remove_client(app_id, client_id) end)
    |> return_result_or_error
  end

  defp do_remove_client(app_id, client_id) do
    :ok = :mnesia.delete {@clients, {app_id, client_id}}
  end

  @impl Singyeong.Store
  def get_app_clients(app_id) do
    :mnesia.transaction(fn -> do_get_app_clients(app_id) end)
    |> return_read_result_or_error(@apps, app_id)
  end

  defp do_get_app_clients(app_id) do
    :mnesia.read({@apps, app_id})
    |> case do
      [] ->
        mapset = MapSet.new()
        :ok = :mnesia.write {@apps, app_id, mapset}
        mapset

      [{@apps, ^app_id, mapset}] ->
        mapset
    end
  end

  @impl Singyeong.Store
  def client_exists?(app_id, client_id) do
    case get_client(app_id, client_id) do
      {:ok, client} -> client != nil
      {:error, _} -> false
    end
  end

  @impl Singyeong.Store
  def count_clients do
    size = :mnesia.table_info @clients, :size
    {:ok, size}
  end

  @impl Singyeong.Store
  def get_clients(count) do
    :mnesia.transaction(fn ->
      # Ugh matchspecs are fucking awful to write
      :mnesia.select @clients, [{{@clients, :"$1", :"$2"}, [], [:"$$"]}], count, :read
    end)
    |> return_select_result_or_error
  end

  @impl Singyeong.Store
  def validate_metadata(data) do
    checked_data =
      Enum.map data, fn {key, %{"type" => type, "value" => value}} ->
        # For every key in the map, we ensure that the metadata entry
        # is well-formed, as well as that the metadata key is not forbidden.
        # If a kv pair passes all checks, it's appended to the output. If it
        # doesn't pass, a descriptive error is generated and returned.
        cond do
          Types.type_exists?(type) and key not in Metadata.forbidden_keys() ->
            atom_type = String.to_atom type
            cond do
              Types.get_type(type).validate.(value) and atom_type == :list ->
                # Mnesia does not allow us to query `x in list types of things
                # easily. This makes sense as that's not exactly an O(1) query
                # to make. Instead, we reduce the list into a keymap that holds
                # the relevant data, so that Mnesia can do an O(1) lookup.
                reduced_list =
                  value
                  |> Enum.with_index
                  |> Enum.reduce(%{}, fn {x, i}, acc ->
                    if Map.has_key?(acc, x) do
                      # Given a list, we store the item in the map, and a list
                      # containing all of its indices. To extract it as a nice
                      # for ex. the metadata query endpoint, we can simply map
                      # those values into a new list, and then merge everything
                      # together, sort by index, and call it a day.
                      # However, mapping these values into plain old lists
                      # doesn't work well enough for what we need. Instead, to
                      # allow for faster queryring with ex. array indexes down
                      # the road, we store them as map keys.
                      Map.put acc, x, Map.put(acc[x], i, nil)
                    else
                      Map.put acc, x, %{i => nil}
                    end
                  end)

                {:ok, {atom_type, key, reduced_list}}

              Types.get_type(type).validate.(value) ->
                {:ok, {atom_type, key, value}}

              true ->
                {:error, {key, "#{key}: value fails validation for '#{type}'"}}
            end

          not Types.type_exists?(type) ->
            {:error, {key, "#{key}: type '#{type}' doesn't exists"}}

          key in Metadata.forbidden_keys() ->
            {:error, {key, "#{key}: forbidden metadata key"}}
        end
      end

    errors = Enum.filter checked_data, &Kernel.===(elem(&1, 0), :error)

    if errors == [] do
      {types, validated} =
        Enum.reduce checked_data, {%{}, %{}}, fn {:ok, {type, key, value}}, {types, values} ->
          {Map.put(types, key, type), Map.put(values, key, value)}
        end

      {:ok, {types, validated}}
    else
      error_messages =
        errors
        |> Enum.map(&elem(&1, 1))
        |> Map.new

      {:error, error_messages}
    end
  end

  @impl Singyeong.Store
  def query(%Query{} = query) do
    {:ok, matching_clients} =
      @clients
      |> Lethe.new
      |> Lethe.select(:client)
      |> Lethe.limit(:all)
      |> with_application(query)
      |> with_restricted(query)
      |> with_ops(query)
      |> Lethe.compile
      |> Lethe.run
      |> case do
        {:ok, clients} ->
          __MODULE__.QueryHelpers.select clients, query

        {:error, _} = err ->
          err
      end

    matching_clients
  end

  defp with_application(lethe, %Query{application: app}) do
    if app != nil do
      lethe |> Lethe.where(^app == map_get(:app_id, :client))
    else
      lethe
    end
  end

  defp with_restricted(lethe, %Query{restricted: restricted?}) do
    if restricted? do
      lethe
    else
      lethe |> Lethe.where(map_get("restricted", map_get(&:metadata, :client)) == false)
    end
  end

  defp with_ops(lethe, %Query{ops: ops}) do
    Enum.reduce ops, lethe, fn
      {_op, {_key, _value}} = operation, query ->
        __MODULE__.QueryHelpers.compile_op query, operation

      {_op, args} = operation, query when is_list args ->
        __MODULE__.QueryHelpers.compile_op query, operation
    end
  end

  defp return_select_result_or_error(mnesia_result) do
    case mnesia_result do
      {:atomic, [{match, _}]} ->
        {:ok, match}

      {:atomic, {match, _}} when is_list(match) ->
        # If we have this ridiculous select return result, it's suddenly really
        # not simple.
        # The data that gets returned looks like:
        #
        #   {
        #     :atomic,
        #     {
        #       [
        #         [key, value],
        #         rest...
        #       ],
        #       {
        #         op,
        #         table,
        #         {?, pid},
        #         node,
        #         storage backend,
        #         {ref, ?, ?, ref, ?, ?},
        #         ?,
        #         ?,
        #         ?,
        #         query
        #       }
        #     }
        #   }
        #
        # and we just care about the matches in the first element of the tuple
        # that comes after the :atomic.

        # {:ok, Enum.map(match, fn [_key, value] -> value end)}
        {:ok, Enum.map(match, &(&1 |> tl |> hd))}

      {:atomic, []} ->
        {:ok, []}

      {:atomic, :"$end_of_table"} ->
        {:ok, []}

      {:aborted, reason} ->
        {:error, {:transaction_aborted, reason}}
    end
  end

  defp return_read_result_or_error(mnesia_result, table, id) do
    case mnesia_result do
      {:atomic, nil} ->
        {:ok, nil}

      {:atomic, []} ->
        {:ok, nil}

      {:atomic, [{^table, ^id, value}]} ->
        {:ok, value}

      {:atomic, value} ->
        {:ok, value}

      {:aborted, reason} ->
        {:error, {:transaction_aborted, reason}}
    end
  end

  defp return_result_or_error(mnesia_result) do
    case mnesia_result do
      {:atomic, res} ->
        {:ok, res}

      {:aborted, reason} ->
        {:error, {:transaction_aborted, reason}}
    end
  end

  def clients, do: @clients

  defmodule QueryHelpers do
    @moduledoc """
    Query helpers for the Mnesia store. This module is the actual
    implementation of all the query ops and selectors, converting them from
    신경 form to Mnesia form via [Lethe](https://queer.gg/lethe).
    """

    alias Singyeong.Mnesia.Store

    ## Functional ops ##

    defp op_eq(lethe, key, value) do
      # TODO: is_map_key(^key, map_get(&:metadata, :client)) and
      Lethe.where lethe, map_get(^key, map_get(&:metadata, :client)) == ^value
    end

    defp op_ne(lethe, key, value) do
      Lethe.where lethe, map_get(^key, map_get(&:metadata, :client)) != ^value
    end

    defp op_gt(lethe, key, value) do
      Lethe.where lethe, map_get(^key, map_get(&:metadata, :client)) > ^value
    end

    defp op_gte(lethe, key, value) do
      Lethe.where lethe, map_get(^key, map_get(&:metadata, :client)) >= ^value
    end

    defp op_lt(lethe, key, value) do
      Lethe.where lethe, map_get(^key, map_get(&:metadata, :client)) < ^value
    end

    defp op_lte(lethe, key, value) do
      Lethe.where lethe, map_get(^key, map_get(&:metadata, :client)) <= ^value
    end

    defp op_in(lethe, key, value) do
      Lethe.where lethe, is_map_key(map_get(^key, map_get(&:metadata, :client)), ^value)
    end

    defp op_nin(lethe, key, value) do
      Lethe.where lethe, not is_map_key(map_get(^key, map_get(&:metadata, :client)), ^value)
    end

    defp op_contains(lethe, key, value) do
      Lethe.where lethe, is_map_key(^value, map_get(^key, map_get(&:metadata, :client)))
    end

    defp op_ncontains(lethe, key, value) do
      Lethe.where lethe, not is_map_key(^value, map_get(^key, map_get(&:metadata, :client)))
    end

    ## Logical ops ##

    defp op_and(lethe, args) do
      and_op =
        Enum.reduce args, nil, fn expr, acc ->
          compiled_expr =
            Store.clients()
            |> Lethe.new
            |> Lethe.select(:client)
            |> compile_op(expr)
            |> Map.from_struct
            |> Map.get(:ops)
            |> hd

          case acc do
            nil ->
              compiled_expr

            _ ->
              {:andalso, compiled_expr, acc}
          end
        end

      Lethe.where_raw lethe, and_op
    end

    defp op_or(lethe, args) do
      or_op =
        Enum.reduce args, nil, fn expr, acc ->
          compiled_expr =
            Store.clients()
            |> Lethe.new
            |> Lethe.select(:client)
            |> compile_op(expr)
            |> Map.from_struct
            |> Map.get(:ops)
            |> hd

          case acc do
            nil ->
              compiled_expr

            _ ->
              {:orelse, compiled_expr, acc}
          end
        end

      Lethe.where_raw lethe, or_op
    end

    defp op_nor(lethe, args) do
      or_op =
        Enum.reduce args, nil, fn expr, acc ->
          compiled_expr =
            Store.clients()
            |> Lethe.new
            |> Lethe.select(:client)
            |> compile_op(expr)
            |> Map.from_struct
            |> Map.get(:ops)
            |> hd

          case acc do
            nil ->
              compiled_expr

            _ ->
              {:orelse, compiled_expr, acc}
          end
        end

      Lethe.where_raw lethe, {:not, or_op}
    end

    ## Selectors ##

    defp selector_min(clients, field) do
      Enum.min_by clients, &(&1.metadata[field])
    end

    defp selector_max(clients, field) do
      Enum.max_by clients, &(&1.metadata[field])
    end

    defp selector_avg(clients, field) do
      avg = Enum.reduce(clients, fn sum, score -> sum + score end)
      Enum.min_by clients, &(&1.metadata[field] - avg)
    end

    ## Helpers ##

    def compile_op(query, {op, {key, value}}) do
      case op do
        :op_eq -> op_eq query, key, value
        :op_ne -> op_ne query, key, value
        :op_gt -> op_gt query, key, value
        :op_gte -> op_gte query, key, value
        :op_lt -> op_lt query, key, value
        :op_lte -> op_lte query, key, value
        :op_in -> op_in query, key, value
        :op_nin -> op_nin query, key, value
        :op_contains -> op_contains query, key, value
        :op_ncontains -> op_ncontains query, key, value
      end
    end

    def compile_op(query, {op, args}) when is_list(args) do
      case op do
        :op_and -> op_and query, args
        :op_or -> op_or query, args
        :op_nor -> op_nor query, args
      end
    end

    def select(clients, %Query{selector: {op, key}}) do
      res =
        op
        |> Atom.to_string
        |> String.replace("$", "selector_")
        |> String.to_atom
        |> case do
          :selector_min ->
            selector_min clients, key

          :selector_max ->
            selector_max clients, key

          :selector_avg ->
            selector_avg clients, key
        end

      {:ok, [res]}
    end

    def select(clients, _) do
      {:ok, clients}
    end
  end
end
