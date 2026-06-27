defmodule LapsusCoordinator.Presence do
  @moduledoc """
  Tracks which peers are online and what they offer.

  The coordinator's discovery half (see `doc/tech/design.md` §2.1): each connected
  peer is tracked on a shared lobby topic with metadata (role, offered models,
  capacity). Consumers query this roster to find a provider for a given model.
  """
  use Phoenix.Presence,
    otp_app: :lapsus_coordinator,
    pubsub_server: LapsusCoordinator.PubSub
end
