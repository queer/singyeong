defmodule Singyeong.Metadata.MnesiaStore do
  alias Singyeong.Metadata.Types

  @clients :clients
  @metadata :metadata

  @doc """
  Initialize the Mnesia-backed metadata store. Creates the schema, starts
  Mnesia, and creates the metadata and clients tables.
  """
  @spec initialize() :: :ok
  def initialize do
    :mnesia.create_schema []
    :mnesia.start()
    :mnesia.create_table @metadata, [attributes: [:composite_key, :value]]
    :mnesia.create_table @clients, [attributes: [:app_id, :client_ids]]
    :ok
  end

  @doc """
  Shut down the Mnesia metadata store.

  **WARNING: THIS WILL DELETE ALL YOUR METADATA**
  """
  @spec shutdown() :: :ok
  def shutdown do
    :mnesia.delete_table @metadata
    :mnesia.delete_table @clients
    :mnesia.stop()
    :mnesia.delete_schema []
    :ok
  end

  @doc """
  Add a client with the given app id and client id
  """
  @spec add_client(binary(), binary()) :: :ok | {:error, binary()}
  def add_client(app_id, client_id) do
    unless client_exists?(app_id, client_id) do
      :mnesia.transaction(fn ->
        clients = :mnesia.wread {@clients, app_id}
        # If we have the app id already, put the client id in the existing set
        # Otherwise, just put it into a new set
        case clients do
          [data] ->
            {@clients, ^app_id, clients} = data
            :mnesia.write {@clients, app_id, MapSet.put(clients, client_id)}
          _ ->
            :mnesia.write {@clients, app_id, MapSet.new([client_id])}
        end
      end)
      :ok
    else
      {:error, "#{client_id} already a member of #{app_id}"}
    end
  end

  @doc """
  Get all clients for the given app id. Returns a `MapSet` of known client ids.
  """
  @spec get_clients(binary()) :: {:ok, MapSet.t} | {:error, {binary(), tuple()}}
  def get_clients(app_id) do
    res =
      :mnesia.transaction(fn ->
        :mnesia.wread {@clients, app_id}
      end)
    case res do
      {:atomic, [data]} ->
        {@clients, ^app_id, clients} = data
        {:ok, clients}
      {:atomic, []} ->
        {:ok, MapSet.new()}
      {:aborted, reason} ->
        {:error, {"mnesia transaction aborted", reason}}
    end
  end

  @doc """
  Check if the given client id is registered as a client for the given
  application id.
  """
  @spec client_exists?(binary(), binary()) :: boolean()
  def client_exists?(app_id, client_id) do
    {:ok, clients} = get_clients app_id
    MapSet.member? clients, client_id
  end

  @doc """
  Delete the client with the given id from the set of known clients for the
  given app id.
  """
  @spec delete_client(binary(), binary()) :: :ok
  def delete_client(app_id, client_id) do
    :mnesia.transaction(fn ->
      clients = :mnesia.wread {@clients, app_id}
      # Only delete if we have the app id already registered
      case clients do
        [data] ->
          {@clients, ^app_id, clients} = data
          :mnesia.write {@clients, app_id, MapSet.delete(clients, client_id)}
        _ ->
          ""
      end
    end)
    :ok
  end

  @doc """
  Validate that the incoming metadata update has valid types. Used when
  receiving metadata over a client's websocket connection. Returns the
  validated and cleaned (ie. stripped of incoming type information) metadata
  values ready for updating.
  """
  @spec validate_metadata(%{optional(binary()) => any()}) :: {:ok, %{optional(binary()) => any()}} | {:error, binary()}
  def validate_metadata(data) when is_map(data) do
    res =
      data
      |> Map.keys
      |> Enum.reduce([], fn(key, acc) ->
        key_data = data[key]
        if is_map(key_data) and length(Map.keys(key_data)) == 2
          and Map.has_key?(key_data, "type") and Map.has_key?(key_data, "value")
          and Map.has_key?(Types.types(), key_data["type"])
        do
          value = key_data["value"]
          type = Types.types()[key_data["type"]]
          [type.validation_function.(value) | acc]
        else
          [false | acc]
        end
      end)
      |> Enum.all?
    if res do
      cleaned =
        data
        |> Map.keys
        |> Enum.reduce(%{}, fn(key, acc) ->
          key_data = data[key]
          value = key_data["value"]
          Map.put acc, key, value
        end)
      {:ok, cleaned}
    else
      {:error, "invalid metadata"}
    end
  end

  @doc """
  Update a single metadata key for the given app/client id pair.
  """
  @spec update_metadata(binary(), binary(), binary(), any()) :: :ok | {:error, {binary(), tuple()}}
  def update_metadata(app_id, client_id, key, value) do
    if client_exists?(app_id, client_id) do
      res =
        :mnesia.transaction(fn ->
          :mnesia.write {@metadata, {app_id, client_id, key}, value}
        end)
      case res do
        {:atomic, _} ->
          :ok
        {:aborted, reason} ->
          {:error, {"mnesia transaction aborted", reason}}
      end
    else
      {:error, {"client not valid for app id", {app_id, client_id}}}
    end
  end

  @doc """
  Bulk-update the metadata for the given app/client id pair. The keys in the
  provided metadata map become the metadata keys, and the mapped values become
  the respective metadata values. Metadata keys MUST be binaries.
  """
  @spec update_metadata(binary(), binary(), %{optional(binary()) => any()}) :: :ok | {:error, {binary(), tuple()}}
  def update_metadata(app_id, client_id, metadata) do
    if client_exists?(app_id, client_id) do
      res =
        :mnesia.transaction(fn ->
          metadata
          |> Map.keys
          |> Enum.each(fn key ->
            :mnesia.write {@metadata, {app_id, client_id, key}, metadata[key]}
          end)
        end)
      case res do
        {:atomic, _} ->
          :ok
        {:aborted, reason} ->
          {:error, {"mnesia transaction aborted", reason}}
      end
    else
      {:error, {"client not valid for app id", {app_id, client_id}}}
    end
  end

  @doc """
  Get all known metadata for the given app/client id pair. Returns a map on
  success.
  """
  @spec get_metadata(binary(), binary()) :: {:ok, %{optional(binary()) => any()}} | {:error, {binary(), tuple()}}
  def get_metadata(app_id, client_id) do
    res =
      :mnesia.transaction(fn ->
        :mnesia.match_object {@metadata, {app_id, client_id, :_}, :_}
      end)
    case res do
      {:atomic, out} ->
        mapped_out =
          out
          |> Enum.reduce(%{}, fn chunk, acc ->
            {@metadata, {^app_id, ^client_id, key}, value} = chunk
            Map.put acc, key, value
          end)
        {:ok, mapped_out}
      {:aborted, reason} ->
        {:error, {"mnesia transaction aborted", reason}}
    end
  end

  @doc """
  Get the value of a single metadata key for the given app/client id pair.
  """
  @spec get_metadata(binary(), binary(), binary()) :: {:ok, any()} | {:error, {binary(), tuple()}}
  def get_metadata(app_id, client_id, key) do
    res =
      :mnesia.transaction(fn ->
        :mnesia.match_object {@metadata, {app_id, client_id, key}, :_}
      end)
    case res do
      {:atomic, [out]} ->
        {@metadata, {^app_id, ^client_id, ^key}, value} = out
        {:ok, value}
      {:atomic, []} ->
        {:ok, nil}
      {:aborted, reason} ->
        {:error, {"mnesia transaction aborted", reason}}
    end
  end
end
