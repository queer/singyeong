defmodule Singyeong.QueueCase do
  use ExUnit.CaseTemplate
  alias Singyeong.Queue

  using do
    quote do
      # Copied from channel_case.ex
      use Phoenix.ChannelTest
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

      def queue_name, do: "test_queue_#{abs(System.monotonic_time(:nanosecond))}_#{:rand.uniform(abs(System.monotonic_time(:nanosecond)))}"
    end
  end

  # This is defined as a macro so that tests using it can pass a proper pattern
  # and not just have match hell.
  defmacro assert_queued(queue_name, pattern) do
    quote do
      {:ok, queue} = Queue.dump(unquote(queue_name))
      queue
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
end
