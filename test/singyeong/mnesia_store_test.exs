defmodule Singyeong.MnesiaStoreTest do
  use ExUnit.Case
  doctest Singyeong.MnesiaStore
  alias Singyeong.MnesiaStore

  setup do
    MnesiaStore.initialize()

    on_exit fn ->
      MnesiaStore.shutdown()
    end
  end

  test "that adding clients works" do
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

  test "that checking that a client exists works" do
    MnesiaStore.add_client "test-app-1", "client-1"
    assert MnesiaStore.client_exists? "test-app-1", "client-1"
  end

  test "that adding an existing client fails" do
    {:ok, clients} = MnesiaStore.get_clients "test-app-1"
    assert 0 == MapSet.size(clients)

    add_res = MnesiaStore.add_client "test-app-1", "client-1"
    assert :ok == add_res

    {:ok, clients} = MnesiaStore.get_clients "test-app-1"
    assert 1 == MapSet.size(clients)
    assert MapSet.member?(clients, "client-1")

    add_res = MnesiaStore.add_client "test-app-1", "client-1"
    {status, _msg} = add_res
    assert :error == status
  end

  test "that deleting clients works" do
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

  test "that updating single metadata key works" do
    {:ok, clients} = MnesiaStore.get_clients "test-app-1"
    assert 0 == MapSet.size(clients)

    MnesiaStore.add_client "test-app-1", "client-1"

    metadata_update_res = MnesiaStore.update_metadata "test-app-1", "client-1", "key", "value"
    assert :ok == metadata_update_res
    {:ok, data} = MnesiaStore.get_metadata "test-app-1", "client-1", "key"
    assert "value" == data
  end

  test "that updating many metadata keys works" do
    {:ok, clients} = MnesiaStore.get_clients "test-app-1"
    assert 0 == MapSet.size(clients)

    MnesiaStore.add_client "test-app-1", "client-1"

    metadata_update_res = MnesiaStore.update_metadata "test-app-1", "client-1", "key", "value"
    assert :ok == metadata_update_res
    metadata_update_res = MnesiaStore.update_metadata "test-app-1", "client-1", "key-2", "value 2"
    assert :ok == metadata_update_res

    {:ok, data} = MnesiaStore.get_metadata "test-app-1", "client-1", "key"
    assert "value" == data
    {:ok, data} = MnesiaStore.get_metadata "test-app-1", "client-1", "key-2"
    assert "value 2" == data
  end

  test "that bulk-updating metadata keys works" do
    {:ok, clients} = MnesiaStore.get_clients "test-app-1"
    assert 0 == MapSet.size(clients)

    MnesiaStore.add_client "test-app-1", "client-1"

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

  test "that bulk-fetching metadata keys works" do
    {:ok, clients} = MnesiaStore.get_clients "test-app-1"
    assert 0 == MapSet.size(clients)

    MnesiaStore.add_client "test-app-1", "client-1"

    metadata_update_res = MnesiaStore.update_metadata "test-app-1", "client-1", %{
      "key" => "value",
      "key-2" => "value 2",
    }
    assert :ok == metadata_update_res

    {:ok, data} = MnesiaStore.get_metadata "test-app-1", "client-1"
    assert "value" == data["key"]
    assert "value 2" == data["key-2"]
  end

  test "that metadata validation works" do
    MnesiaStore.add_client "test-app-1", "client-1"
    metadata = %{
      "a" => %{
        "type" => "string",
        "value" => "a",
      },
      "b" => %{
        "type" => "integer",
        "value" => 123
      }
    }
    {status, data} = MnesiaStore.validate_metadata metadata
    assert :ok == status

    {status, _data} = MnesiaStore.validate_metadata data
    assert :error == status
  end

  test "that handling pids works" do
    pid = spawn fn -> "" end
    MnesiaStore.add_socket "test-app-1", "client-1", pid
    {:ok, out} = MnesiaStore.get_socket "test-app-1", "client-1"
    assert pid == out

    del_res = MnesiaStore.remove_socket "test-app-1", "client-1"
    assert :ok == del_res

    {:ok, out} = MnesiaStore.get_socket "test-app=1", "client-1"
    assert nil == out
  end

  test "that add / fetch / delete tags works" do
    tags = ["test", "cool", "memes"]
    MnesiaStore.add_client "test-app-1", "client-1"

    set_res = MnesiaStore.set_tags "test-app-1", "client-1", tags
    assert set_res == :ok

    assert {:ok, fetched_tags} = MnesiaStore.get_tags "test-app-1", "client-1"
    # This is so dumb ;_;
    # The problem is that since we're using a :bag table in Mnesia, when we
    # read tags from the table, reducing them into a list the performant way
    # means that we need to append them to the BEGINNING, and reversing
    # in-place is (imo) an unnecessary step to take.
    assert tags == Enum.reverse(fetched_tags)

    del_res = MnesiaStore.delete_tags "test-app-1", "client-1"
    assert {:ok, empty_tags} = MnesiaStore.get_tags "test-app-1", "client-1"
    assert :ok == del_res
    assert nil == empty_tags
  end

  test "that matching application ids by tags works" do
    many_tags = ["test", "cool", "memes"]
    one_tag = ["test-tag"]
    some_tags = ["test", "test-tag"]
    fake_tag = ["this-tag-isnt-real"]
    no_tags = []
    MnesiaStore.add_client "test-app-1", "client-1"
    MnesiaStore.add_client "test-app-2", "client-1"
    MnesiaStore.add_client "test-app-3", "client-1"

    set_res_1 = MnesiaStore.set_tags "test-app-1", "client-1", many_tags
    assert set_res_1 == :ok
    set_res_2 = MnesiaStore.set_tags "test-app-2", "client-1", one_tag
    assert set_res_2 == :ok
    set_res_3 = MnesiaStore.set_tags "test-app-3", "client-1", some_tags
    assert set_res_3 == :ok

    {:ok, many_match} = MnesiaStore.get_applications_with_tags many_tags
    assert ["test-app-1"] == many_match

    # This should match multiple applications, as the intent of this function
    # is that it returns ALL app ids that have the given tags. Since we're only
    # testing for a single tag - one shared between both of them - it should be
    # returning both app ids.
    {:ok, one_match} = MnesiaStore.get_applications_with_tags one_tag
    assert ["test-app-2", "test-app-3"] == one_match

    {:ok, some_match} = MnesiaStore.get_applications_with_tags some_tags
    assert ["test-app-3"] == some_match

    {:ok, no_match} = MnesiaStore.get_applications_with_tags fake_tag
    assert [] == no_match

    {:ok, no_tags_given_match} = MnesiaStore.get_applications_with_tags no_tags
    assert [] == no_tags_given_match
  end
end
