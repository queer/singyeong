defmodule Singyeong.Metadata do
  @moduledoc """
  Holds constant information about specific metadata values that are reserved
  for internal use.
  """

  alias Singyeong.Utils

  @last_heartbeat_time "last_heartbeat_time"
  @ip "ip"
  @restricted "restricted"
  @encoding "encoding"
  @namespace "namespace"

  # We reserve some keys for internal use while still allowing them to be
  # metadata-queried on.
  @forbidden_keys [
    @last_heartbeat_time,
    @ip,
    @restricted,
    @encoding,
    @namespace,
  ]

  def last_heartbeat_time, do: @last_heartbeat_time
  def ip, do: @ip
  def restricted, do: @restricted
  def encoding, do: @encoding
  def namespace, do: @namespace

  def forbidden_keys, do: @forbidden_keys

  def base(restricted?, encoding, client_ip, ns) do
    %{
      last_heartbeat_time() => Utils.now(),
      restricted() => restricted?,
      encoding() => encoding,
      ip() => client_ip,
      namespace() => ns,
    }
  end

  def base_types do
    %{
      last_heartbeat_time() => :integer,
      restricted() => :boolean,
      encoding() => :string,
      ip() => :string,
      namespace() => :string,
    }
  end
end
