defmodule Singyeong.Env do
  import System, only: [get_env: 1]

  def auth,       do: get_env "AUTH"
  def port,       do: get_env "PORT"
  def clustering, do: get_env "CLUSTERING"
  def cookie,     do: get_env "COOKIE"
  def redis_dsn,  do: get_env "REDIS_DSN"
end
