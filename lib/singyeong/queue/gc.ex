defmodule Singyeong.Queue.Gc do
  @moduledoc """
  A background worker that occasionally garbage-collects a queue. The queue
  garbage collection process is moving unacked messages to the DLQ, and moving
  dead messages from the DLQ back into the main queue. An unacked message
  cannot be moved unacked -> DLQ -> main queue in a single pass.
  """
  use GenServer
  alias Singyeong.{
    Config,
    Queue,
  }
  require Logger

  def start_link(opts) do
    GenServer.start_link __MODULE__, opts, name: :"singyeong:queue:gc:#{opts[:name]}"
  end

  def init(opts) do
    Process.send_after self(), :gc, interval()
    {:ok, opts}
  end

  def handle_info(:gc, state) do
    name = state[:name]
    Logger.debug "[QUEUE] [GC] [#{name}] Starting GC pass..."
    case Queue.check_acks_and_dlq(name) do
      :ok ->
        Process.send_after self(), :gc, interval()
        Logger.debug "[QUEUE] [GC] [#{name}] Finished GC pass!"
        {:noreply, state}

      {:error, msg} = err ->
        Logger.error "[QUEUE] [GC] [#{name}] Couldn't finish GC pass: #{inspect err}"
        {:stop, msg, state}
    end
  end

  defp interval, do: Config.queue_gc_interval()
end
