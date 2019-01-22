defmodule Singyeong.Env do
  def auth, do: System.get_env("AUTH")
end
