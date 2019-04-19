defmodule Singyeong.Metadata do
  @last_heartbeat_time "last_heartbeat_time"
  @ip "ip"
  @restricted "restricted"
  @etf "etf"

  @forbidden_keys [
    @last_heartbeat_time,
    @ip,
    @restricted,
    @etf,
  ]

  def last_heartbeat_time, do: @last_heartbeat_time
  def ip, do: @ip
  def restricted, do: @restricted
  def etf, do: @etf

  def forbidden_keys, do: @forbidden_keys
end
