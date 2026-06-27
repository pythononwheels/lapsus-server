defmodule LapsusCoordinator.Repo.Migrations.CreateJobs do
  use Ecto.Migration

  def change do
    # One row per completed (booked) job — powers the usage dashboards.
    create table(:jobs) do
      add :provider_id, :string, null: false
      add :consumer_id, :string, null: false
      add :model, :string, null: false
      add :in_tokens, :integer, null: false, default: 0
      add :out_tokens, :integer, null: false, default: 0
      add :cc, :integer, null: false, default: 0
      add :ok, :boolean, null: false, default: true

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:jobs, [:provider_id, :inserted_at])
    create index(:jobs, [:consumer_id, :inserted_at])
    create index(:jobs, [:model])
  end
end
