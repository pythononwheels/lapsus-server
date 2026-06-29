defmodule LapsusCoordinator.LedgerTest do
  use LapsusCoordinator.DataCase, async: true
  import Ecto.Query

  alias LapsusCoordinator.Ledger
  alias LapsusCoordinator.Ledger.Hold
  alias LapsusCoordinator.Repo
  alias LapsusCore.Identity

  defp peer_id, do: Identity.generate().peer_id

  test "ensure_peer creates a peer with the starter faucet" do
    id = peer_id()
    peer = Ledger.ensure_peer(id)
    assert peer.peer_id == id
    assert peer.balance_cc == Ledger.faucet_cc()
    assert Ledger.balance(id) == Ledger.faucet_cc()
  end

  test "ensure_peer is idempotent (faucet granted once)" do
    id = peer_id()
    Ledger.ensure_peer(id)
    Ledger.ensure_peer(id)
    assert Ledger.balance(id) == Ledger.faucet_cc()
  end

  test "balance is 0 for an unknown peer" do
    assert Ledger.balance(peer_id()) == 0
  end

  test "record_job moves credits from consumer to provider" do
    consumer = peer_id()
    provider = peer_id()
    Ledger.ensure_peer(consumer)
    Ledger.ensure_peer(provider)

    assert {:ok, _entry} = Ledger.record_job(consumer, provider, 30, "job-1")
    assert Ledger.balance(consumer) == Ledger.faucet_cc() - 30
    assert Ledger.balance(provider) == Ledger.faucet_cc() + 30
  end

  test "record_job fails when the consumer lacks funds" do
    consumer = peer_id()
    provider = peer_id()

    assert {:error, :insufficient_funds} =
             Ledger.record_job(consumer, provider, Ledger.faucet_cc() + 1, "job-x")

    # Balances untouched on failure.
    assert Ledger.balance(consumer) == Ledger.faucet_cc()
    assert Ledger.balance(provider) == Ledger.faucet_cc()
  end

  test "grant adds credits" do
    id = peer_id()
    Ledger.ensure_peer(id)
    assert {:ok, _} = Ledger.grant(id, 500, "grant")
    assert Ledger.balance(id) == Ledger.faucet_cc() + 500
  end

  describe "escrow holds" do
    test "reserve holds credits: available drops, balance unchanged" do
      c = peer_id()
      assert :ok = Ledger.reserve(c, "req-1", 40)
      assert Ledger.balance(c) == Ledger.faucet_cc()
      assert Ledger.held(c) == 40
      assert Ledger.available(c) == Ledger.faucet_cc() - 40
    end

    test "reserve fails when available is too low" do
      c = peer_id()
      Ledger.ensure_peer(c)
      assert {:error, :insufficient_funds} = Ledger.reserve(c, "req-big", Ledger.faucet_cc() + 1)
      assert Ledger.held(c) == 0
    end

    test "a second reserve can't exceed the remaining available balance" do
      c = peer_id()
      Ledger.ensure_peer(c)
      half = div(Ledger.faucet_cc(), 2)
      assert :ok = Ledger.reserve(c, "r-a", half)
      assert {:error, :insufficient_funds} = Ledger.reserve(c, "r-b", Ledger.faucet_cc())
      assert :ok = Ledger.reserve(c, "r-c", 10)
    end

    test "reserve is idempotent per request_id" do
      c = peer_id()
      assert :ok = Ledger.reserve(c, "req-id", 25)
      assert :ok = Ledger.reserve(c, "req-id", 25)
      assert Ledger.held(c) == 25
    end

    test "record_job settles against the hold (clears it) and books the actual cost" do
      c = peer_id()
      p = peer_id()
      assert :ok = Ledger.reserve(c, "job-9", 50)
      assert Ledger.held(c) == 50

      assert {:ok, _} = Ledger.record_job(c, p, 30, "job-9")
      assert Ledger.held(c) == 0
      assert Ledger.balance(c) == Ledger.faucet_cc() - 30
      assert Ledger.balance(p) == Ledger.faucet_cc() + 30
      assert Ledger.available(c) == Ledger.balance(c)
    end

    test "release frees a hold without booking" do
      c = peer_id()
      assert :ok = Ledger.reserve(c, "req-rel", 60)
      assert Ledger.held(c) == 60
      assert :ok = Ledger.release("req-rel")
      assert Ledger.held(c) == 0
      assert Ledger.balance(c) == Ledger.faucet_cc()
    end

    test "sweep_expired releases stale holds, keeps fresh ones" do
      c = peer_id()
      assert :ok = Ledger.reserve(c, "fresh", 10)
      assert :ok = Ledger.reserve(c, "stale", 20)
      old = DateTime.add(DateTime.utc_now(), -3600, :second)
      Repo.update_all(from(h in Hold, where: h.request_id == "stale"), set: [inserted_at: old])

      assert Ledger.held(c) == 30
      assert Ledger.sweep_expired(300) == 1
      assert Ledger.held(c) == 10
    end
  end
end
