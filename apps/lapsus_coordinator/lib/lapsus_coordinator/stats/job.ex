defmodule LapsusCoordinator.Stats.Job do
  @moduledoc "A completed (booked) job record — the raw data behind the usage dashboards."
  use Ecto.Schema
  import Ecto.Changeset

  schema "jobs" do
    field :provider_id, :string
    field :consumer_id, :string
    field :model, :string
    field :in_tokens, :integer, default: 0
    field :out_tokens, :integer, default: 0
    field :cc, :integer, default: 0
    field :ok, :boolean, default: true

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(job, attrs) do
    job
    |> cast(attrs, [:provider_id, :consumer_id, :model, :in_tokens, :out_tokens, :cc, :ok])
    |> validate_required([:provider_id, :consumer_id, :model])
  end
end
