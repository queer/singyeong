defmodule Singyeong.Config do
  @moduledoc false

  def store_mod, do: c :store

  def auth, do: c :auth
  def port, do: c :port
  def topologies, do: c :topologies

  def queue_config, do: c :queue
  def queue_ack_timeout, do: queue_config() |> Keyword.get(:ack_timeout)
  def queue_dlq_time, do: queue_config() |> Keyword.get(:dlq_time)
  def queue_group_size, do: queue_config() |> Keyword.get(:group_size)
  def queue_gc_interval, do: queue_config() |> Keyword.get(:gc_interval)

  def metadata_config, do: c :metadata
  def metadata_queue_interval, do: metadata_config() |> Keyword.get(:queue_interval)
  def metadata_update_strategy, do: metadata_config() |> Keyword.get(:update_strategy)

  def raft_config, do: c :raft
  def raft_zone, do: raft_config() |> Keyword.get(:zone)

  defp c(k) when is_atom(k), do: Application.get_env :singyeong, k
end
