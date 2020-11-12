defmodule Singyeong.Config do
  @moduledoc false

  def store_mod, do: c :store

  def auth, do: c :auth
  def port, do: c :port
  def clustering, do: c :clustering
  def cookie, do: c :cookie
  def redis_dsn, do: c :redis_dsn

  def queue_config, do: c :queue
  def queue_ack_timeout, do: queue_config() |> Keyword.get(:ack_timeout)
  def queue_dlq_time, do: queue_config() |> Keyword.get(:dlq_time)
  def queue_group_size, do: queue_config() |> Keyword.get(:group_size)

  def metadata_config, do: c :metadata
  def metadata_queue_interval, do: metadata_config() |> Keyword.get(:queue_interval)

  defp c(k) when is_atom(k), do: Application.get_env :singyeong, k
end
