defmodule Singyeong.Metadata.MnesiaStoreTest do
  use ExUnit.Case
  doctest Singyeong.Metadata.MnesiaStore
  alias Singyeong.Metadata.MnesiaStore

  setup do
    MnesiaStore.initialize()

    on_exit fn ->
      MnesiaStore.shutdown()
    end
  end

  test "adding clients works" do
    MnesiaStore.add_client "test-app-1", "client-1"
    MnesiaStore.add_client "test-app-1", "client-2"
    MnesiaStore.add_client "test-app-1", "client-3"
    MnesiaStore.add_client "test-app-1", "client-4"

    MnesiaStore.add_client "test-app-2", "client-1"
    MnesiaStore.add_client "test-app-2", "client-2"

    {:ok, clients} = MnesiaStore.get_clients "test-app"
    assert 0 == MapSet.size(clients)

    {:ok, clients1} = MnesiaStore.get_clients "test-app-1"
    assert 4 == MapSet.size(clients1)
    assert MapSet.member?(clients1, "client-1")
    assert MapSet.member?(clients1, "client-2")
    assert MapSet.member?(clients1, "client-3")
    assert MapSet.member?(clients1, "client-4")

    {:ok, clients2} = MnesiaStore.get_clients "test-app-2"
    assert 2 == MapSet.size(clients2)
    assert MapSet.member?(clients2, "client-1")
    assert MapSet.member?(clients2, "client-2")
  end

  test "deleting clients works" do
    {:ok, clients} = MnesiaStore.get_clients "test-app-1"
    assert 0 == MapSet.size(clients)

    MnesiaStore.add_client "test-app-1", "client-1"
    {:ok, clients} = MnesiaStore.get_clients "test-app-1"
    assert 1 == MapSet.size(clients)
    assert MapSet.member?(clients, "client-1")

    MnesiaStore.delete_client "test-app-1", "client-1"
    {:ok, clients} = MnesiaStore.get_clients "test-app-1"
    assert 0 == MapSet.size(clients)
  end

  test "updating single metadata key works" do
    {:ok, clients} = MnesiaStore.get_clients "test-app-1"
    assert 0 == MapSet.size(clients)

    MnesiaStore.add_client "test-app-1", "client-1"
    {:ok, clients} = MnesiaStore.get_clients "test-app-1"
    assert 1 == MapSet.size(clients)
    assert MapSet.member?(clients, "client-1")

    metadata_update_res = MnesiaStore.update_metadata "test-app-1", "client-1", "key", "value"
    assert :ok == metadata_update_res
    {:ok, data} = MnesiaStore.get_metadata "test-app-1", "client-1", "key"
    assert "value" == data
  end

  test "updating many metadata keys works" do
    {:ok, clients} = MnesiaStore.get_clients "test-app-1"
    assert 0 == MapSet.size(clients)

    MnesiaStore.add_client "test-app-1", "client-1"
    {:ok, clients} = MnesiaStore.get_clients "test-app-1"
    assert 1 == MapSet.size(clients)
    assert MapSet.member?(clients, "client-1")

    metadata_update_res = MnesiaStore.update_metadata "test-app-1", "client-1", "key", "value"
    assert :ok == metadata_update_res
    metadata_update_res = MnesiaStore.update_metadata "test-app-1", "client-1", "key-2", "value 2"
    assert :ok == metadata_update_res

    {:ok, data} = MnesiaStore.get_metadata "test-app-1", "client-1", "key"
    assert "value" == data
    {:ok, data} = MnesiaStore.get_metadata "test-app-1", "client-1", "key-2"
    assert "value 2" == data
  end

  test "bulk-updating metadata keys works" do
    {:ok, clients} = MnesiaStore.get_clients "test-app-1"
    assert 0 == MapSet.size(clients)

    MnesiaStore.add_client "test-app-1", "client-1"
    {:ok, clients} = MnesiaStore.get_clients "test-app-1"
    assert 1 == MapSet.size(clients)
    assert MapSet.member?(clients, "client-1")

    metadata_update_res = MnesiaStore.update_metadata "test-app-1", "client-1", %{
      "key" => "value",
      "key-2" => "value 2",
    }
    assert :ok == metadata_update_res

    {:ok, data} = MnesiaStore.get_metadata "test-app-1", "client-1", "key"
    assert "value" == data
    {:ok, data} = MnesiaStore.get_metadata "test-app-1", "client-1", "key-2"
    assert "value 2" == data
  end

  test "bulk-fetching metadata keys works" do
    {:ok, clients} = MnesiaStore.get_clients "test-app-1"
    assert 0 == MapSet.size(clients)

    MnesiaStore.add_client "test-app-1", "client-1"
    {:ok, clients} = MnesiaStore.get_clients "test-app-1"
    assert 1 == MapSet.size(clients)
    assert MapSet.member?(clients, "client-1")

    metadata_update_res = MnesiaStore.update_metadata "test-app-1", "client-1", %{
      "key" => "value",
      "key-2" => "value 2",
    }
    assert :ok == metadata_update_res

    {:ok, data} = MnesiaStore.get_metadata "test-app-1", "client-1"
    assert "value" == data["key"]
    assert "value 2" == data["key-2"]
  end
end
