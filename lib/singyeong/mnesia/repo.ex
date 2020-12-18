defmodule Singyeong.Mnesia.Repo do
  use Ecto.Repo,
    otp_app: :singyeong,
    adapter: Ecto.Adapters.Mnesia
end
