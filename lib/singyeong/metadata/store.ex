defmodule Singyeong.Metadata.Store do
  @pool_size 5

  def pool_spec(dsn) do
    children =
      for i <- 0..(@pool_size - 1) do
        %{
          id: {Redix, i},
          start: {Redix, :start_link, [dsn, [name: :"redix_#{i}"]]},
        }
      end

    # This child spec would go under the app's supervisor:
    %{
      id: RedixSupervisor,
      type: :supervisor,
      start: {Supervisor, :start_link, [children, [strategy: :one_for_one]]}
    }
  end

  def add_to_store(app_id, client_id) when is_binary(app_id) and is_binary(client_id) do
    #
  end

  defp command(command) do
    Redix.command(:"redix_#{random_index()}", command)
  end

  defp random_index() do
    rem(System.unique_integer([:positive]), 5)
  end
end
