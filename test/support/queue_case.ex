defmodule Singyeong.QueueCase do
  @moduledoc """
  Test helpers for queue-related tests.
  """
  use ExUnit.CaseTemplate
  alias Singyeong.Queue

  using do
    quote do
      # Copied from channel_case.ex
      import Phoenix.ChannelTest
      import Singyeong.QueueCase

      @endpoint SingyeongWeb.Endpoint
      @moduletag capture_log: true

      setup_all do
        on_exit fn ->
          case RaftFleet.deactivate() do
            :ok -> nil
            # It's possible that tests finish before a leader election is
            # complete, so this is fine. There's only 1 possible node in tests
            # that use this case, so there's no real worries.
            {:error, :no_leader} -> nil
            err -> raise "unknown raft exit state: #{inspect err}"
          end
        end
      end

      setup do
        queue = queue_name()
        :ok = Queue.create! queue
        on_exit fn ->
          Queue.flush queue
        end
        %{queue: queue}
      end
    end
  end

  def queue_name, do: "test_queue_#{abs(System.monotonic_time(:nanosecond))}_#{:rand.uniform(abs(System.monotonic_time(:nanosecond)))}"

  # Welcome to macro hell.

  defmacro assert_queued(queue_name, pattern) do
    quote do
      unquote(queue_name)
      |> Queue.dump_full_state
      |> elem(1)
      |> Map.from_struct
      |> Map.get(:queue)
      |> :queue.to_list
      |> Enum.any?(fn item ->
        case item do
          unquote(pattern) ->
            true

          _ ->
            false
        end
      end)
      |> assert
    end
  end

  defmacro refute_queued(queue_name, pattern) do
    quote do
      unquote(queue_name)
      |> Queue.dump_full_state
      |> elem(1)
      |> Map.from_struct
      |> Map.get(:queue)
      |> :queue.to_list
      |> Enum.any?(fn item ->
        case item do
          unquote(pattern) ->
            true

          _ ->
            false
        end
      end)
      |> refute
    end
  end

  defmacro assert_dlq(queue_name, pattern) do
    quote do
      unquote(queue_name)
      |> Queue.dump_full_state
      |> elem(1)
      |> Map.from_struct
      |> Map.get(:dlq)
      |> Enum.any?(fn item ->
        case item.message do
          unquote(pattern) ->
            true

          _ ->
            false
        end
      end)
      |> assert
    end
  end

  defmacro refute_dlq(queue_name, pattern) do
    quote do
      unquote(queue_name)
      |> Queue.dump_full_state
      |> elem(1)
      |> Map.from_struct
      |> Map.get(:dlq)
      |> Enum.any?(fn item ->
        case item.message do
          unquote(pattern) ->
            true

          _ ->
            false
        end
      end)
      |> refute
    end
  end

  defmacro assert_ack(queue_name, id, pattern) do
    quote do
      unquote(queue_name)
      |> Queue.dump_full_state
      |> elem(1)
      |> Map.from_struct
      |> Map.get(:unacked_messages)
      |> Map.get(unquote(id))
      |> case do
        %{message: unquote(pattern)} ->
          true

        _ ->
          false
      end
      |> assert
    end
  end

  defmacro refute_ack(queue_name, id, pattern) do
    quote do
      unquote(queue_name)
      |> Queue.dump_full_state
      |> elem(1)
      |> Map.from_struct
      |> Map.get(:unacked_messages)
      |> Map.get(unquote(id))
      |> case do
        %{message: unquote(pattern)} ->
          true

        _ ->
          false
      end
      |> refute
    end
  end

  def assert_awaiting(queue_name, client_id) do
    queue_name
    |> Queue.dump_full_state
    |> elem(1)
    |> Map.from_struct
    |> Map.get(:pending_clients)
    |> Enum.any?(fn {_, client} -> client == client_id end)
    |> assert
  end

  def refute_awaiting(queue_name, client_id) do
    queue_name
    |> Queue.dump_full_state
    |> elem(1)
    |> Map.from_struct
    |> Map.get(:pending_clients)
    |> Enum.any?(fn {_, client} -> client == client_id end)
    |> refute
  end
end
