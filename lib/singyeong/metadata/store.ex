defmodule Singyeong.Metadata.Store do
  @moduledoc """
  신경 stores metadata using redis as its backing store. Redis is used mainly
  for speed reasons - it's Probably Fast Enough:tm: for the kind of use-case
  that something like 신경 has (ie. it's unlikely that you'll be doing >100k
  metadata updates / second from a host of client applications).

  When you IDENTIFY your client with 신경, it stores your client name in one
  list, and then stores the client id under a list of client ids for the
  specified application id. Metadata kv pairs that get stored for your client's
  id are then stored under a hash for that specific client id.

  Effectively, we get a structure like the following:

  ```
  app_id => [a, b, c]
  a => %{key => value, key2 => value2, ...}
  ```

  and then when you query on a specific client id, 신경 can easily scan all
  registered clients for a given app id.

  This means that, for a given client id `X`, if you have `M` clients, and each
  client has `N` metadata keys, 신경 can scan the metadata for a routing query
  with `C` keys in `O(M * C)`. As lookups of a client's key are O(1) due to how
  Redis hashes work, it effectively just becomes `client count * query key count`
  which is just `M * C`. However, given that each metadata query becomes a
  command issued to Redis, it's advised that you try to keep metadata key count
  low so that you can work with a larger number of clients. 신경 will try to
  do Redis commands efficiently (ex. via pipelining), but it may still have
  performance implications for a very large number of clients / metadata keys.

  Internally, 신경 will store the list of clients for an app id as a Redis set,
  mainly so that we don't end up with a race condition around removing list
  elements (read: because set elements can be removed directly).
  """

  alias Singyeong.Metadata.Types

  @pool_size 5

  def pool_spec(dsn) do
    children =
      for i <- 0..(@pool_size - 1) do
        %{
          id: {Redix, i},
          start: {Redix, :start_link, [dsn, [name: :"redix_#{i}"]]},
        }
      end

    # This child spec would go under the app's supervisor:
    %{
      id: RedixSupervisor,
      type: :supervisor,
      start: {Supervisor, :start_link, [children, [strategy: :one_for_one]]}
    }
  end

  @doc """
  Add a client to the known clients for an app id.
  """
  def add_client_to_store(app_id, client_id) when is_binary(app_id) and is_binary(client_id) do
    command ["SADD", format_key("application", app_id), client_id]
  end

  @doc """
  Check if a client exists for a given app id.
  """
  def store_has_client?(app_id, client_id) when is_binary(app_id) and is_binary(client_id) do
    command ["SISMEMBER", format_key("application", app_id), client_id]
  end

  def get_all_clients(app_id) when is_binary(app_id) do
    command ["SMEMBERS", format_key("application", app_id)]
  end

  @doc """
  Filter out all clients who haven't heartbeated for a while
  """
  def filter_old_clients(app_id) when is_binary(app_id) do
    {:ok, clients} = get_all_clients app_id
  end

  def remove_client(app_id, client_id) when is_binary(app_id) and is_binary(client_id) do
    command ["SREM", format_key("application", app_id), client_id]
    # Clean up associated metadata
    command ["DEL", format_key("client", client_id)]
  end

  @doc """
  Given a mapping of metadata typings, validate that the metadata is actually
  valid data for the associated types.
  """
  def validate_metadata?(data) when is_map(data) do
    data
    |> Map.keys
    |> Enum.reduce([], fn(x, acc) ->
      d = data[x]
      v = d["value"]
      type = Types.types()[String.to_atom(d["type"])]
      acc ++ [type.validation_function.(v)]
    end)
    |> Enum.all?
  end

  @doc """
  Bulk-update the metadata for a client.
  """
  def update_metadata(data, client_id) when is_map(data) and is_binary(client_id) do
    # Reduce metadata map into a list of commands and pipeline it
    data
    |> Map.keys
    |> Enum.reduce([], fn(x, acc) ->
        key =
          if is_atom(x) do
            Atom.to_string x
          else
            x
          end
        acc ++ [["HSET", format_key("client", client_id), key, data[x]]]
      end)
    |> pipeline
  end

  def get_metadata(client_id) when is_binary(client_id) do
    {:ok, data} = command ["HGETALL", format_key("client", client_id)]
    data
    |> Enum.chunk_every(2)
    |> Enum.reduce(%{}, fn(x, acc) ->
      [a, b] = x
      Map.put(acc, a, b)
    end)
  end

  def format_key(type, key) when is_binary(type) and is_binary(key) do
    "singyeong:metadata:#{type}:#{key}"
  end

  def pipeline(commands) when is_list(commands) do
    Redix.pipeline :"redix_#{random_index()}", commands
  end

  def command(command) do
    Redix.command :"redix_#{random_index()}", command
  end

  defp random_index() do
    rem System.unique_integer([:positive]), 5
  end
end
