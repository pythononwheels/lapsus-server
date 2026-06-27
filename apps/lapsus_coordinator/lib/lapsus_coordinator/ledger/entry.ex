defmodule LapsusCoordinator.Ledger.Entry do
  @moduledoc "An append-only credit movement (audit trail)."
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(faucet job clawback grant)

  schema "ledger_entries" do
    field :kind, :string
    field :amount_cc, :integer
    field :from_peer_id, :string
    field :to_peer_id, :string
    field :job_ref, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:kind, :amount_cc, :from_peer_id, :to_peer_id, :job_ref])
    |> validate_required([:kind, :amount_cc])
    |> validate_inclusion(:kind, @kinds)
  end

  def kinds, do: @kinds
end
