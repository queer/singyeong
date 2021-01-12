defmodule Singyeong.StoreTest do
  use ExUnit.Case, async: false
  alias Singyeong.Store
  alias Singyeong.Store.Client

  @app_id "app"
  @client_id "client"

  setup do
    Store.start()

    on_exit fn ->
      Store.stop()
    end
  end

  describe "add_client/1" do
    test "it works" do
      {:ok, out} = Store.add_client client()
      assert :ok == out
    end
  end

  describe "get_client/2" do
    test "it works" do
      {:ok, :ok} = Store.add_client client()
      {:ok, out} = Store.get_client @app_id, @client_id
      assert client() == out
    end
  end

  describe "update_client/1" do
    test "it works" do
      {:ok, :ok} = Store.add_client client()
      {:ok, out} = Store.get_client @app_id, @client_id
      assert client() == out
      {:ok, out} = Store.update_client updated_client()
      assert updated_client() == out
    end
  end

  describe "remove_client/1" do
    test "it works" do
      client = client()
      {:ok, :ok} = Store.add_client client
      {:ok, ^client} = Store.get_client @app_id, @client_id
      {:ok, out} = Store.remove_client client
      assert :ok == out
    end
  end

  describe "get_app_clients/1" do
    test "it works" do
      client = client()
      {:ok, :ok} = Store.add_client client
      {:ok, clients} = Store.get_app_clients @app_id

      assert 1 == MapSet.size(clients)
      assert MapSet.member?(clients, client.client_id)
    end
  end

  describe "client_exists?/2" do
    test "it works" do
      {:ok, :ok} = Store.add_client client()
      assert Store.client_exists?(@app_id, @client_id)
    end
  end

  describe "count_clients/0" do
    test "it works" do
      assert {:ok, 0} == Store.count_clients()
      {:ok, :ok} = Store.add_client client()
      assert {:ok, 1} == Store.count_clients()
    end
  end

  describe "get_clients/1" do
    test "it works" do
      {:ok, :ok} = Store.add_client client()
      {:ok, count} = Store.count_clients()
      assert 1 == count
      {:ok, clients} = Store.get_clients count
      assert client() in clients
    end
  end

  describe "validate_metadata/1" do
    test "it works" do
      metadata =
        %{
          "key" => %{
            "type" => "string",
            "value" => "value",
          },
          "key2" => %{
            "type" => "integer",
            "value" => 123,
          },
        }

      {:ok, out} = Store.validate_metadata metadata
      assert "value" == Map.get(out, "key")
      assert 123 == Map.get(out, "key2")
    end

    test "it rejects invalid metadata" do
      metadata =
        %{
          "key" => %{
            "type" => "string",
            "value" => 1_234_567_890,
          },
        }

      {:error, out} = Store.validate_metadata metadata
      assert Map.get(out, "key") =~ ~r/.*value fails validation.*/
    end
  end

  defp client do
    %Client{
      app_id: @app_id,
      client_id: @client_id,
      # TODO: Make this reflect reality
      metadata: %{},
      socket_pid: self(),
      socket_ip: nil,
      queues: [],
    }
  end

  defp updated_client do
    client = client()
    %{client | metadata: Map.put(client.metadata, "test", "value")}
  end
end
