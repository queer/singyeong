defmodule Singyeong.Queue.Gc do
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

  defp interval, do: min(Config.queue_dlq_time(), Config.queue_ack_timeout())
end
