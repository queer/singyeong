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

      setup_all do
        :ok = RaftFleet.activate "test_zone"
        :ok = Queue.create! @queue_name

        on_exit fn ->
          :ok = RaftFleet.deactivate()
        end
      end

      setup do
        on_exit fn ->
          Queue.flush @queue_name
        end
      end

      def queue_name, do: @queue_name
    end
  end

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
