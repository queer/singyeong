defmodule Singyeong.Store.Mnesia do
  @moduledoc false

  alias Singyeong.Metadata
  alias Singyeong.Metadata.Types
  alias Singyeong.Store.Client

  @behaviour Singyeong.Store

  @clients :clients
  @apps :apps

  @impl Singyeong.Store
  def start do
    :mnesia.create_schema []
    :mnesia.start()

    :mnesia.create_table @clients, [attributes: [:composite_id, :client]]
    :mnesia.add_table_index @clients, :composite_id

    :mnesia.create_table @apps, [attributes: [:app_id, :app]]
    :mnesia.add_table_index @apps, :app_id
    :ok
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
  def add_client(%Client{client_id: id} = client) do
    if client_exists?(id) do
      raise "#{id}: can't add to #{client.app_id}: already exists"
    end
    :mnesia.transaction(fn -> do_add_client(client) end)
    |> return_result_or_error
  end

  defp do_add_client(%Client{app_id: app_id, client_id: id} = client) do
    :ok = :mnesia.write {@clients, id, client}
    {:ok, mapset} = get_app_clients app_id
    mapset = MapSet.put mapset, id
    :ok = :mnesia.write {@apps, app_id, mapset}
  end

  @impl Singyeong.Store
  def update_client(%Client{} = client) do
    :mnesia.transaction(fn -> do_update_client(client) end)
    |> return_result_or_error
  end

  defp do_update_client(%Client{app_id: app_id, client_id: id} = client) do
    mapset = get_clients app_id
    if MapSet.member?(mapset, id) do
      raise "Couldn't add client #{id} to app #{app_id}: it already exists"
    end
    :ok = :mnesia.write {@clients, client}
    mapset = MapSet.put mapset, id
    :ok = :mnesia.write {@apps, app_id, mapset}
  end

  @impl Singyeong.Store
  def get_client(client_id) do
    :mnesia.transaction(fn -> do_get_client(client_id) end)
    |> return_read_result_or_error(@clients, client_id)
  end

  defp do_get_client(client_id) do
    case :mnesia.read({@clients, client_id}) do
      [{@clients, ^client_id, client}] ->
        {:ok, app_clients} = get_app_clients client.app_id
        unless MapSet.member?(app_clients, client_id) do
          raise "Couldn't get client #{client_id}: not a member of app #{client.app_id}"
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
    :mnesia.transaction(fn -> do_remove_client(client_id) end)
    |> return_result_or_error
  end

  defp do_remove_client(client_id) do
    :ok = :mnesia.delete {@clients, client_id}
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
  def client_exists?(client_id) do
    case get_client(client_id) do
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
    res =
      :mnesia.transaction fn ->
        # Ugh matchspecs are fucking awful to write
        :mnesia.select @clients, [{{@clients, [:_], :_}, [], [:"$$"]}], count, :read
      end

    case res do
      {:atomic, [{match, _}]} ->
        {:ok, match}

      {:atomic, []} ->
        {:ok, []}

      {:atomic, :"$end_of_table"} ->
        {:ok, []}

      {:aborted, reason} ->
        {:error, {"mnesia transaction aborted", reason}}
    end
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
            if Types.get_type(type).validate.(value) do
              {:ok, {key, value}}
            else
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
      # TODO: This should probably be Enum.reduce/3
      validated =
        checked_data
        |> Enum.map(&elem(&1, 1))
        |> Map.new

      {:ok, validated}
    else
      error_messages =
        errors
        |> Enum.map(&elem(&1, 1))
        |> Map.new

      {:error, error_messages}
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
end
