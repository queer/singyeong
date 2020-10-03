defmodule Singyeong.Config do
  @moduledoc false

  def store_mod, do: Application.get_env :singyeong, :store

  def auth, do: Application.get_env :singyeong, :auth
  def port, do: Application.get_env :singyeong, :port
  def clustering, do: Application.get_env :singyeong, :clustering
  def cookie, do: Application.get_env :singyeong, :cookie
  def redis_dsn, do: Application.get_env :singyeong, :redis_dsn
end
