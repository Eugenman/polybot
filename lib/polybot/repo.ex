defmodule Polybot.Repo do
  use Ecto.Repo,
    otp_app: :polybot,
    adapter: Ecto.Adapters.Postgres
end
