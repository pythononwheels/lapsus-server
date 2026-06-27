defmodule LapsusCoordinator.Ledger do
  @moduledoc """
  Compute-Credit ledger — the accounting half of the coordinator (§2.1, §4).

  Balances are cached on `peers` for fast lookup and always equal the sum of the
  append-only `ledger_entries`. All credit movements go through here so they stay
  atomic and auditable. The coordinator never touches inference traffic — it only
  books the credits a completed P2P job is worth.
  """
  import Ecto.Query

  alias Ecto.Multi
  alias LapsusCoordinator.Ledger.{Entry, Peer}
  alias LapsusCoordinator.Repo

  # Tiny starter grace for a new identity — enough to try the network, not to
  # leech (see §4.4). The real income is serving compute. Configurable because dev
  # needs a generous faucet (real earning isn't wired yet); prod stays tiny.
  @default_faucet_cc 100

  @doc "Starter-faucet amount granted to a brand-new peer (config `:faucet_cc`)."
  def faucet_cc, do: Application.get_env(:lapsus_coordinator, :faucet_cc, @default_faucet_cc)

  @doc """
  Ensure a peer row exists, creating it (with the starter faucet) if missing.
  Returns the `Peer`.
  """
  @spec ensure_peer(String.t()) :: Peer.t()
  def ensure_peer(peer_id) when is_binary(peer_id) do
    case Repo.get_by(Peer, peer_id: peer_id) do
      nil -> create_peer_with_faucet(peer_id)
      peer -> peer
    end
  end

  @doc "Current balance in CC (0 if the peer is unknown)."
  @spec balance(String.t()) :: integer()
  def balance(peer_id) do
    case Repo.get_by(Peer, peer_id: peer_id) do
      nil -> 0
      peer -> peer.balance_cc
    end
  end

  @doc "CC earned by serving jobs since 00:00 UTC today."
  @spec earned_today(String.t()) :: integer()
  def earned_today(peer_id) do
    start = DateTime.new!(Date.utc_today(), ~T[00:00:00], "Etc/UTC")

    Repo.one(
      from(e in Entry,
        where: e.kind == "job" and e.to_peer_id == ^peer_id and e.inserted_at >= ^start,
        select: sum(e.amount_cc)
      )
    ) || 0
  end

  @doc "Balance + earned-today snapshot for a peer (for the provider dashboard)."
  @spec stats(String.t()) :: %{balance: integer(), earned_today: integer()}
  def stats(peer_id), do: %{balance: balance(peer_id), earned_today: earned_today(peer_id)}

  @doc """
  Book a completed job: debit the consumer and credit the provider by `cc`,
  atomically, with an audit entry. Fails if the consumer lacks the funds.
  """
  @spec record_job(String.t(), String.t(), pos_integer(), String.t() | nil) ::
          {:ok, Entry.t()} | {:error, :insufficient_funds | term()}
  def record_job(consumer_id, provider_id, cc, job_ref \\ nil)
      when is_integer(cc) and cc > 0 do
    if job_ref && job_booked?(job_ref) do
      {:error, :duplicate_job}
    else
      do_record_job(consumer_id, provider_id, cc, job_ref)
    end
  end

  defp job_booked?(job_ref) do
    Repo.exists?(from(e in Entry, where: e.kind == "job" and e.job_ref == ^job_ref))
  end

  defp do_record_job(consumer_id, provider_id, cc, job_ref) do
    ensure_peer(consumer_id)
    ensure_peer(provider_id)

    Multi.new()
    |> Multi.run(:debit, fn repo, _ ->
      {count, _} =
        repo.update_all(
          from(p in Peer, where: p.peer_id == ^consumer_id and p.balance_cc >= ^cc),
          inc: [balance_cc: -cc]
        )

      if count == 1, do: {:ok, count}, else: {:error, :insufficient_funds}
    end)
    |> Multi.update_all(
      :credit,
      from(p in Peer, where: p.peer_id == ^provider_id),
      inc: [balance_cc: cc]
    )
    |> Multi.insert(
      :entry,
      Entry.changeset(%Entry{}, %{
        kind: "job",
        amount_cc: cc,
        from_peer_id: consumer_id,
        to_peer_id: provider_id,
        job_ref: job_ref
      })
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{entry: entry}} -> {:ok, entry}
      {:error, :debit, reason, _changes} -> {:error, reason}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  @doc "Grant credits to a peer (e.g. faucet top-up, paid-pool payout)."
  @spec grant(String.t(), pos_integer(), String.t()) :: {:ok, Entry.t()} | {:error, term()}
  def grant(peer_id, cc, kind \\ "grant") when is_integer(cc) and cc > 0 do
    ensure_peer(peer_id)

    Multi.new()
    |> Multi.update_all(
      :credit,
      from(p in Peer, where: p.peer_id == ^peer_id),
      inc: [balance_cc: cc]
    )
    |> Multi.insert(
      :entry,
      Entry.changeset(%Entry{}, %{kind: kind, amount_cc: cc, to_peer_id: peer_id})
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{entry: entry}} -> {:ok, entry}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp create_peer_with_faucet(peer_id) do
    faucet = faucet_cc()

    {:ok, peer} =
      %Peer{}
      |> Peer.changeset(%{peer_id: peer_id, balance_cc: faucet})
      |> Repo.insert(on_conflict: :nothing, conflict_target: :peer_id)

    # on_conflict :nothing returns a struct without id when a concurrent insert
    # won the race — that peer already has its faucet, so just refetch it.
    case peer.id do
      nil ->
        Repo.get_by!(Peer, peer_id: peer_id)

      _ ->
        Repo.insert!(
          Entry.changeset(%Entry{}, %{kind: "faucet", amount_cc: faucet, to_peer_id: peer_id})
        )

        peer
    end
  end
end
