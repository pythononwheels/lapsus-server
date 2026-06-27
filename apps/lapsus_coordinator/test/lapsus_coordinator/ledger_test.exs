defmodule LapsusCoordinator.LedgerTest do
  use LapsusCoordinator.DataCase, async: true

  alias LapsusCoordinator.Ledger
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
end
