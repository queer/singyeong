defmodule Singyeong.Redis do
  @moduledoc """
  Sets up pooled Redix connections for transparent usage.
  TODO: Should probably just use poolboy or similar here...
  """

  alias Singyeong.Env

  @pool_size 5

  def child_spec(_opts) do
    url = Env.redis_dsn()
    %URI{host: host, userinfo: userinfo} = URI.parse(url)
    children =
      if userinfo != nil and userinfo != "" do
        password =
          userinfo
          |> String.split(":", trim: true)
          |> hd
        for i <- 0..(@pool_size - 1) do
          Supervisor.child_spec {Redix, [name: :"redix_#{i}", host: host, password: password]}, id: {Redix, i}
        end
      else
        for i <- 0..(@pool_size - 1) do
          Supervisor.child_spec {Redix, [name: :"redix_#{i}", host: host]}, id: {Redix, i}
        end
      end

    # Spec for the supervisor that will supervise the Redix connections.
    %{
      id: RedixSupervisor,
      type: :supervisor,
      start: {Supervisor, :start_link, [children, [strategy: :one_for_one]]}
    }
  end

  def q(cmd), do: command cmd

  def command(command) do
    Redix.command :"redix_#{random_index()}", command
  end

  defp random_index() do
    [:positive]
    |> System.unique_integer
    |> rem(@pool_size)
  end
end
