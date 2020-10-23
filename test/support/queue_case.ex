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
      @queue_name "test"

      setup do
        :ok = RaftFleet.activate "test_zone"
        :ok = Queue.create! @queue_name

        on_exit fn ->
          Queue.flush @queue_name
          :ok = RaftFleet.deactivate()
        end
      end

      def queue_name, do: @queue_name
    end
  end

  # TODO: Traverse the entire queue to search for this message
  defmacro assert_queued(queue_name, pattern) do
    quote do
      {:ok, peek} = Queue.peek(unquote(queue_name))
      assert peek = unquote(pattern)
    end
  end
end
