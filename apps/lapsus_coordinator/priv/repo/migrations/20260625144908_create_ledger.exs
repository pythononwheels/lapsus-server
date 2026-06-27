defmodule LapsusCoordinator.Repo.Migrations.CreateLedger do
  use Ecto.Migration

  def change do
    # One row per peer: current balance + reputation.
    create table(:peers) do
      add :peer_id, :string, null: false
      add :balance_cc, :integer, null: false, default: 0
      add :reputation, :float, null: false, default: 0.0

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:peers, [:peer_id])

    # Append-only ledger of credit movements (audit trail; balances are cached on
    # `peers` for fast lookup but always equal the sum of entries).
    create table(:ledger_entries) do
      # :faucet | :job | :clawback | :grant
      add :kind, :string, null: false
      add :amount_cc, :integer, null: false
      add :from_peer_id, :string
      add :to_peer_id, :string
      add :job_ref, :string

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:ledger_entries, [:from_peer_id])
    create index(:ledger_entries, [:to_peer_id])
  end
end
