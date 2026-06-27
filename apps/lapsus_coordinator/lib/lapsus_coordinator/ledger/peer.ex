defmodule LapsusCoordinator.Ledger.Peer do
  @moduledoc "A peer's cached balance and reputation, keyed by `peer_id`."
  use Ecto.Schema
  import Ecto.Changeset

  schema "peers" do
    field :peer_id, :string
    field :balance_cc, :integer, default: 0
    field :reputation, :float, default: 0.0

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(peer, attrs) do
    peer
    |> cast(attrs, [:peer_id, :balance_cc, :reputation])
    |> validate_required([:peer_id])
    |> validate_number(:balance_cc, greater_than_or_equal_to: 0)
    |> unique_constraint(:peer_id)
  end
end
