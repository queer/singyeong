defmodule Singyeong.MnesiaStore do
  alias Singyeong.Metadata
  alias Singyeong.Metadata.Types

  @clients :clients
  @metadata :metadata
  @sockets :sockets
  @socket_ips :socket_ips
  @tags :tags

  ####################
  ## INITIALIZATION ##
  ####################

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
    :mnesia.create_table @sockets, [attributes: [:composite_key, :socket_pid]]
    :mnesia.create_table @socket_ips, [attributes: [:composite_key, :socket_pid]]
    # The tags table is created as a bag so that we can have a less-painful
    # time trying to fetch and read the client's tags in a way that allows us
    # to do tag comparisons for eg. connects
    :mnesia.create_table @tags, [attributes: [:composite_key, :tags], type: :bag]
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
    :mnesia.delete_table @sockets
    :mnesia.delete_table @socket_ips
    :mnesia.delete_table @tags
    :mnesia.stop()
    :mnesia.delete_schema []
    :ok
  end

  #############
  ## CLIENTS ##
  #############

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
          # Delete all the metadata
          {:ok, metadata} = get_metadata(app_id, client_id)
          metadata
          |> Map.keys
          |> Enum.each(fn key ->
            :mnesia.delete {@metadata, {app_id, client_id, key}}
          end)
        _ ->
          ""
      end
    end)
    :ok
  end

  ##############
  ## METADATA ##
  ##############

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
        # For every key in the map, we ensure that the metadata entry
        # is well-formed, as well as that the metadata key is not forbidden.
        # If it's NOT forbidden, we validate it, and prepend the
        # validation result it to the accumulator, and then keep going.
        # If it IS forbidden, we prepend false.
        # Once the processing is finished, we check if all values are
        # truthy; any false values means we return an error.
        key_data = data[key]
        if is_map(key_data) and length(Map.keys(key_data)) == 2
          and Map.has_key?(key_data, "type") and Map.has_key?(key_data, "value")
          and Map.has_key?(Types.types(), key_data["type"])
          and key not in Metadata.forbidden_keys()
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
      # If it's valid, we reduce the input to a simple key => value map
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
        :mnesia.read {@metadata, {app_id, client_id, key}}
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

  ############################
  ## WEBSOCKET PIDS AND IPS ##
  ############################

  # Sockets

  @doc """
  Add a socket to the store. Used for actually sending websocket payloads.
  """
  @spec add_socket(binary(), binary(), pid()) :: :ok
  def add_socket(app_id, client_id, pid) do
    :mnesia.transaction(fn ->
      :mnesia.write {@sockets, {app_id, client_id}, pid}
    end)
    :ok
  end

  @doc """
  Return the socket pid with the given composite id, or `nil` if there is none.
  """
  @spec get_socket(binary(), binary()) :: {:ok, pid()} | {:ok, nil} | {:error, {binary(), tuple()}}
  def get_socket(app_id, client_id) do
    res =
      :mnesia.transaction(fn ->
        :mnesia.read {@sockets, {app_id, client_id}}
      end)
    case res do
      {:atomic, [out]} ->
        {@sockets, {^app_id, ^client_id}, pid} = out
        {:ok, pid}
      {:atomic, []} ->
        {:ok, nil}
      {:aborted, reason} ->
        {:error, {"mnesia transaction aborted", reason}}
    end
  end

  @doc """
  Count the number of sockets currently stored. Used for load-balancing.
  """
  @spec count_sockets() :: integer() | {:error, any()}
  def count_sockets do
    :mnesia.table_info @sockets, :size
  end

  @spec get_first_sockets(integer()) :: list()
  def get_first_sockets(count) do
    res =
      :mnesia.transaction(fn ->
        :mnesia.select @sockets, {@sockets, {:_, :_, :_}, :_}, count, :_
      end)
    case res do
      {:atomic, [out]} ->
        {:ok, out}
      {:atomic, []} ->
        {:ok, nil}
      {:aborted, reason} ->
        {:error, {"mnesia transaction aborted", reason}}
    end
  end

  @doc """
  Remove the socket with the given composite id from the store.
  """
  @spec remove_socket(binary(), binary()) :: :ok
  def remove_socket(app_id, client_id) do
    :mnesia.transaction(fn ->
      :mnesia.delete {@sockets, {app_id, client_id}}
    end)
    :ok
  end

  # Socket IPs

  @doc """
  Add a socket ip to the store. Used for proxying HTTP requests.
  """
  @spec add_socket_ip(binary(), binary(), pid()) :: :ok
  def add_socket_ip(app_id, client_id, pid) do
    :mnesia.transaction(fn ->
      :mnesia.write {@socket_ips, {app_id, client_id}, pid}
    end)
    :ok
  end

  @doc """
  Return the socket ip with the given composite id, or `nil` if there is none.
  """
  @spec get_socket_ip(binary(), binary()) :: {:ok, pid()} | {:ok, nil} | {:error, {binary(), tuple()}}
  def get_socket_ip(app_id, client_id) do
    res =
      :mnesia.transaction(fn ->
        :mnesia.read {@socket_ips, {app_id, client_id}}
      end)
    case res do
      {:atomic, [out]} ->
        {@socket_ips, {^app_id, ^client_id}, pid} = out
        {:ok, pid}
      {:atomic, []} ->
        {:ok, nil}
      {:aborted, reason} ->
        {:error, {"mnesia transaction aborted", reason}}
    end
  end

  @doc """
  Remove the socket ip with the given composite id from the store.
  """
  @spec remove_socket_ip(binary(), binary()) :: :ok
  def remove_socket_ip(app_id, client_id) do
    :mnesia.transaction(fn ->
      :mnesia.delete {@socket_ips, {app_id, client_id}}
    end)
    :ok
  end

  ##########
  ## TAGS ##
  ##########

  @doc """
  Set the tags for the client with the given application id.
  """
  @spec set_tags(binary(), binary(), list()) :: :ok | {:error, {binary(), tuple()}}
  def set_tags(app_id, client_id, tags) do
    if client_exists?(app_id, client_id) do
      res =
        :mnesia.transaction(fn ->
          tags |> Enum.each(fn tag ->
            :mnesia.write {@tags, {app_id, client_id}, tag}
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
  Get the tags for the client with the given composite id.

  **NOTE**: This returns tags in the REVERSE order that they were registered
  in! Use Enum.reverse/1 if you need them in the original order.
  """
  @spec get_tags(binary(), binary()) :: {:ok, list()} | {:ok, nil} | {:error, {binary(), tuple()}}
  def get_tags(app_id, client_id) do
    if client_exists?(app_id, client_id) do
      res =
        :mnesia.transaction(fn ->
          :mnesia.read {@tags, {app_id, client_id}}
        end)
      case res do
        {:atomic, tags} when is_list(tags) and length(tags) > 0 ->
          out =
            tags
            |> Enum.reduce([], fn(x, acc) ->
              {@tags, {^app_id, ^client_id}, tag} = x
              [tag | acc]
            end)
          {:ok, out}
        {:atomic, []} ->
          {:ok, nil}
        {:aborted, reason} ->
          {:error, {"mnesia transaction aborted", reason}}
      end
    else
      {:error, {"client not valid for app id", {app_id, client_id}}}
    end
  end

  @doc """
  Deletes the tags for the client with the given composite id. Generally should
  only be called when deleting the client from the store as we don't support
  dynamically changing tags at runtime

  TODO: Support dynamic tag updates?
  """
  @spec delete_tags(binary(), binary()) :: :ok
  def delete_tags(app_id, client_id) do
    # Doesn't really matter what we return here, because if it's not present it
    # won't really make a difference.
    :mnesia.transaction(fn ->
      :mnesia.delete {@tags, {app_id, client_id}}
    end)
    :ok
  end

  @doc """
  Returns a list of application ids that have clients with the given tags. Note
  that this does NOT ensure that all clients for the application id have all
  tags set on them, so you should try to ensure homogeneity by not letting
  clients of the same application set different tags.
  """
  @spec get_applications_with_tags(list()) :: {:ok, list()} | {:error, {binary(), tuple()}}
  def get_applications_with_tags(tags) do
    if tags == [] do
      # Don't even bother if there's no tags to search for
      {:ok, []}
    else
      sorted_tags = Enum.sort tags
      res =
        :mnesia.transaction(fn ->
          apps_with_tags =
            tags
            |> Enum.map(fn tag ->
              # Fetch matching clients from Mnesia
              out = :mnesia.match_object {@tags, {:_, :_}, tag}
              # This turns the list of tags into a list of lists of matching app ids
              out
              |> Enum.map(fn object ->
                {@tags, {app_id, _client_id}, tag} = object
                {app_id, tag}
              end)
            end)
            |> Enum.reduce(%{}, fn(matches, acc) ->
              # Previous step returns a list of lists like
              # [{app_id, tag}, {app_id, tag}, ...]
              # We reduce the list into a map, then merge it into the accumulator
              # map in this step
              map =
                matches
                |> Enum.reduce(%{}, fn({app_id, tag}, inner_acc) ->
                  if Map.has_key?(inner_acc, app_id) do
                    Map.put inner_acc, app_id, [tag | inner_acc[app_id]]
                  else
                    Map.put inner_acc, app_id, [tag]
                  end
                end)
              map
              |> Map.keys
              |> Enum.reduce(acc, fn(app_id, inner_acc) ->
                tags = map[app_id]
                if Map.has_key?(inner_acc, app_id) do
                  # Merge lists
                  # TODO: Can we make this more efficient?
                  Map.put inner_acc, app_id, inner_acc[app_id] ++ tags
                else
                  Map.put inner_acc, app_id, tags
                end
              end)
            end)
          # Filter out only the app ids with the correct keys
          apps_with_tags
          |> Map.keys
          |> Enum.filter(fn(app_id) ->
            sorted_tags == Enum.sort(apps_with_tags[app_id])
          end)
        end)

      case res do
        {:atomic, matches} when is_list(matches) ->
          {:ok, matches}
        {:aborted, reason} ->
          {:error, {"mnesia transaction aborted", reason}}
      end
    end
  end
end
