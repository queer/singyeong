defmodule Singyeong.Store do
  @moduledoc """
  The behaviour used for implementing a metadata store. The default
  implementation is `Singyeong.Store.Mnesia` and should be used as a reference.
  """

  alias Singyeong.Config
  alias Singyeong.Store.Client

  @type app_id() :: String.t()
  @type client_id() :: String.t()
  @type transaction_success(res) :: {:ok, res}
  @type transaction_failure() :: {:error, {:transaction_aborted, term()}}
  @type transaction(res) :: transaction_success(res) | transaction_failure()

  @doc """
  Start the store. Set up database connections or anything else needed.
  """
  @callback start() :: :ok
  defdelegate start, to: Config.store_mod()

  @doc """
  Stop the store. Disconnect from a database or anything else needed.
  """
  @callback stop() :: :ok
  defdelegate stop, to: Config.store_mod()

  @doc """
  Add a client to the store. This has the side-effect of also adding the client
  to the list of clients for its app.
  """
  @callback add_client(Client.t()) :: transaction(:ok)
  defdelegate add_client(client), to: Config.store_mod()

  @doc """
  Returns the client with the given ID. Validates that the client is included
  in the apps client list.
  """
  @callback get_client(app_id(), client_id()) :: transaction(Client.t() | nil)
  defdelegate get_client(app_id, client_id), to: Config.store_mod()

  @doc """
  Updates the given client in-place in the store. This should not have the same
  checks on it that `add_client/1` does.
  """
  @callback update_client(Client.t()) :: transaction(Client.t() | nil)
  defdelegate update_client(client), to: Config.store_mod()

  @doc """
  Removes the client from the store. Has the side-effect of removing the client
  from its app's client list.
  """
  @callback remove_client(Client.t()) :: transaction(:ok)
  defdelegate remove_client(client), to: Config.store_mod()

  @doc """
  Returns all clients for the given app.
  """
  @callback get_app_clients(app_id()) :: transaction(MapSet.t())
  defdelegate get_app_clients(app_id), to: Config.store_mod()

  @doc """
  Returns whether or not the given client exists
  """
  @callback client_exists?(app_id(), client_id()) :: boolean()
  defdelegate client_exists?(app_id, client_id), to: Config.store_mod()

  @doc """
  Counts the number of currently-connected clients. May not return negative
  values.
  """
  @callback count_clients() :: {:ok, non_neg_integer()}
  defdelegate count_clients, to: Config.store_mod()

  @doc """
  Gets the first **N** clients from the store, where **N** is a non-negative
  value.
  """
  @callback get_clients(non_neg_integer()) :: transaction([Client.t()])
  defdelegate get_clients(count), to: Config.store_mod()

  @doc """
  Validate that the incoming metadata update has valid types. Used when
  receiving metadata over a client's websocket connection. Returns the
  validated and cleaned (ie. stripped of incoming type information) metadata
  values ready for updating.
  """
  @callback validate_metadata(%{optional(String.t()) => any()})
    :: {:ok, %{optional(String.t()) => any()}}
       | {:error, %{String.t() => String.t()}}
  defdelegate validate_metadata(metadata), to: Config.store_mod()
end
