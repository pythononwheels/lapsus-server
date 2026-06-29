defmodule LapsusCoordinator.Ledger.Hold do
  @moduledoc "An escrow reservation: credits held for one in-flight request."
  use Ecto.Schema
  import Ecto.Changeset

  schema "holds" do
    field :request_id, :string
    field :consumer_id, :string
    field :provider_id, :string
    field :relay_id, :string
    field :amount_cc, :integer

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(hold, attrs) do
    hold
    |> cast(attrs, [:request_id, :consumer_id, :provider_id, :relay_id, :amount_cc])
    |> validate_required([:request_id, :consumer_id, :amount_cc])
    |> validate_number(:amount_cc, greater_than: 0)
    |> unique_constraint(:request_id)
  end
end
