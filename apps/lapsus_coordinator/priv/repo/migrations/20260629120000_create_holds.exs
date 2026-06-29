defmodule LapsusCoordinator.Repo.Migrations.CreateHolds do
  use Ecto.Migration

  def change do
    # Escrow reservations: credits held for an in-flight request. The consumer's
    # *available* balance is `balance_cc − sum(active holds)`. A hold is cleared
    # when the job settles (receipt booked) or released (failure / timeout reaper).
    create table(:holds) do
      add :request_id, :string, null: false
      add :consumer_id, :string, null: false
      add :provider_id, :string
      add :relay_id, :string
      add :amount_cc, :integer, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:holds, [:request_id])
    create index(:holds, [:consumer_id])
    create index(:holds, [:inserted_at])
  end
end
