defmodule Singyeong.Metadata do
  @last_heartbeat_time "last_heartbeat_time"
  @ip "ip"

  @forbidden_keys [
    @last_heartbeat_time,
    @ip
  ]

  def last_heartbeat_time, do: @last_heartbeat_time
  def ip, do: @ip
  def forbidden_keys, do: @forbidden_keys
end
