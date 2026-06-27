defmodule LapsusCoordinator.Repo do
  use Ecto.Repo,
    otp_app: :lapsus_coordinator,
    adapter: Ecto.Adapters.SQLite3
end
