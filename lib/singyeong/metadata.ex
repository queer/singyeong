defmodule Singyeong.Metadata do
  @moduledoc """
  Holds constant information about specific metadata values that are reserved
  for internal use.
  """

  @last_heartbeat_time "last_heartbeat_time"
  @ip "ip"
  @restricted "restricted"
  @encoding "encoding"

  # We reserve some keys for internal use while still allowing them to be
  # metadata-queried on.
  @forbidden_keys [
    @last_heartbeat_time,
    @ip,
    @restricted,
    @encoding,
  ]

  def last_heartbeat_time, do: @last_heartbeat_time
  def ip, do: @ip
  def restricted, do: @restricted
  def encoding, do: @encoding

  def forbidden_keys, do: @forbidden_keys
end
