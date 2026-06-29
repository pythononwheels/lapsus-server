defmodule LapsusCoordinator.Ledger.Reaper do
  @moduledoc """
  Auto-releases expired escrow holds. A reservation whose job never settles (the
  consumer vanished, the request hung) would otherwise lock those credits forever;
  this frees holds older than the TTL on a periodic sweep.
  """
  use GenServer
  require Logger

  alias LapsusCoordinator.Ledger

  @interval :timer.seconds(60)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    {:ok, schedule()}
  end

  @impl true
  def handle_info(:sweep, state) do
    case Ledger.sweep_expired() do
      n when n > 0 -> Logger.info("[ledger] reaper released #{n} expired escrow hold(s)")
      _ -> :ok
    end

    {:noreply, schedule(state)}
  end

  defp schedule(state \\ %{}) do
    Process.send_after(self(), :sweep, @interval)
    state
  end
end
